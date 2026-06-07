/*
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of Quake III Arena source code.

Quake III Arena source code is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the License,
or (at your option) any later version.

Quake III Arena source code is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Quake III Arena source code; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
*/

#include <stdlib.h>
#include <stdio.h>

#include <SDL3/SDL.h>

#include "qcommon/q_shared.h"
#include "client/client.h"
#include "client/snd_local.h"

extern dma_t		dma;
static SDL_AudioStream *audioStream = NULL;
static SDL_AudioDeviceID dev = 0;
qboolean snd_inited = qfalse;

cvar_t *s_sdlBits;
cvar_t *s_sdlSpeed;
cvar_t *s_sdlChannels;
cvar_t *s_sdlDevSamps;
cvar_t *s_sdlMixSamps;

/* The audio callback. All the magic happens here. */
static int dmapos = 0;
static int dmasize = 0;

/*
===============
SNDDMA_AudioCallback
===============
*/
static void SNDDMA_AudioCallback(void *userdata, SDL_AudioStream *stream, int additional_amount, int total_amount)
{
	int pos = (dmapos * (dma.samplebits/8));
	if (pos >= dmasize)
		dmapos = pos = 0;

	if (!snd_inited)  /* shouldn't happen, but just in case... */
	{
		Uint8 *silence = (Uint8 *)malloc(additional_amount);
		memset(silence, '\0', additional_amount);
		SDL_PutAudioStreamData(stream, silence, additional_amount);
		free(silence);
		return;
	}
	else
	{
		int tobufend = dmasize - pos;  /* bytes to buffer's end. */
		int len1 = additional_amount;
		int len2 = 0;

		if (len1 > tobufend)
		{
			len1 = tobufend;
			len2 = additional_amount - len1;
		}
		SDL_PutAudioStreamData(stream, dma.buffer + pos, len1);
		if (len2 <= 0)
			dmapos += (len1 / (dma.samplebits/8));
		else  /* wraparound? */
		{
			SDL_PutAudioStreamData(stream, dma.buffer, len2);
			dmapos = (len2 / (dma.samplebits/8));
		}
	}

	if (dmapos >= dmasize)
		dmapos = 0;
}

static struct
{
	SDL_AudioFormat	enumFormat;
	const char	*stringFormat;
} formatToStringTable[ ] =
{
	{ SDL_AUDIO_U8,     "SDL_AUDIO_U8" },
	{ SDL_AUDIO_S8,     "SDL_AUDIO_S8" },
	{ SDL_AUDIO_S16LE,  "SDL_AUDIO_S16LE" },
	{ SDL_AUDIO_S16BE,  "SDL_AUDIO_S16BE" },
	{ SDL_AUDIO_S32LE,  "SDL_AUDIO_S32LE" },
	{ SDL_AUDIO_S32BE,  "SDL_AUDIO_S32BE" },
	{ SDL_AUDIO_F32LE,  "SDL_AUDIO_F32LE" },
	{ SDL_AUDIO_F32BE,  "SDL_AUDIO_F32BE" }
};

static const size_t formatToStringTableSize = ARRAY_LEN( formatToStringTable );

/*
===============
SNDDMA_PrintAudiospec
===============
*/
static void SNDDMA_PrintAudiospec(const char *str, const SDL_AudioSpec *spec)
{
	const char	*fmt = NULL;

	Com_Printf( "%s:\n", str );

	for( size_t i = 0; i < formatToStringTableSize; i++ ) {
		if( spec->format == formatToStringTable[ i ].enumFormat ) {
			fmt = formatToStringTable[ i ].stringFormat;
		}
	}

	if( fmt ) {
		Com_Printf( "  Format:   %s\n", fmt );
	} else {
		Com_Printf( "  Format:   " S_COLOR_RED "UNKNOWN (0x%x)\n", (int)spec->format);
	}

	Com_Printf( "  Freq:     %d\n", (int) spec->freq );
	Com_Printf( "  Channels: %d\n", (int) spec->channels );
}

static int SNDDMA_ExpandSampleFrequencyKHzToHz(int khz)
{
	switch (khz)
	{
		default:
		case 44: return 44100;
		case 22: return 22050;
		case 11: return 11025;
	}
}

/*
===============
SNDDMA_Init
===============
*/
qboolean SNDDMA_Init(int sampleFrequencyInKHz)
{
	SDL_AudioSpec desired;
	SDL_AudioSpec obtained;
	int tmp;

	if (snd_inited)
		return qtrue;

	if (!s_sdlBits) {
		s_sdlBits = Cvar_Get("s_sdlBits", "16", CVAR_ARCHIVE_ND);
		s_sdlChannels = Cvar_Get("s_sdlChannels", "2", CVAR_ARCHIVE_ND);
		s_sdlDevSamps = Cvar_Get("s_sdlDevSamps", "0", CVAR_ARCHIVE_ND);
		s_sdlMixSamps = Cvar_Get("s_sdlMixSamps", "0", CVAR_ARCHIVE_ND);
	}

	Com_Printf( "SDL_Init( SDL_INIT_AUDIO )... " );

	if (!SDL_WasInit(SDL_INIT_AUDIO))
	{
		if (!SDL_Init(SDL_INIT_AUDIO))
		{
			Com_Printf( "FAILED (%s)\n", SDL_GetError( ) );
			return qfalse;
		}
	}

	Com_Printf( "OK\n" );

	Com_Printf( "SDL audio driver is \"%s\".\n", SDL_GetCurrentAudioDriver( ) );

	memset(&desired, '\0', sizeof (desired));
	memset(&obtained, '\0', sizeof (obtained));

	tmp = ((int) s_sdlBits->value);
	if ((tmp != 16) && (tmp != 8))
		tmp = 16;

	desired.freq = SNDDMA_ExpandSampleFrequencyKHzToHz(sampleFrequencyInKHz);
	desired.format = ((tmp == 16) ? SDL_AUDIO_S16 : SDL_AUDIO_U8);
	desired.channels = (int) s_sdlChannels->value;

	audioStream = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &desired, SNDDMA_AudioCallback, NULL);
	if ( !audioStream )
	{
		Com_Printf("SDL_OpenAudioDeviceStream() failed: %s\n", SDL_GetError());
		SDL_QuitSubSystem(SDL_INIT_AUDIO);
		return qfalse;
	}

	SNDDMA_PrintAudiospec("SDL_AudioSpec", &desired);

	// dma.samples needs to be big, or id's mixer will just refuse to
	//  work at all; we need to keep it significantly bigger than the
	//  amount of SDL callback samples, and just copy a little each time
	//  the callback runs.
	// 32768 is what the OSS driver filled in here on my system. I don't
	//  know if it's a good value overall, but at least we know it's
	//  reasonable...this is why I let the user override.
	tmp = s_sdlMixSamps->value;
	if (!tmp)
		tmp = 1024 * 2 * 10;  // sane default: ~1024 samples * 2 channels * 10

	if (tmp & (tmp - 1))  // not a power of two? Seems to confuse something.
	{
		int val = 1;
		while (val < tmp)
			val <<= 1;

		tmp = val;
	}

	dmapos = 0;
	dma.samplebits = SDL_AUDIO_BITSIZE(desired.format);
	dma.channels = desired.channels;
	dma.samples = tmp;
	dma.submission_chunk = 1;
	dma.speed = desired.freq;
	dmasize = (dma.samples * (dma.samplebits/8));
	dma.buffer = (byte *)calloc(1, dmasize);

	Com_Printf("Starting SDL audio callback...\n");
	SDL_ResumeAudioDevice(dev);

	Com_Printf("SDL audio initialized.\n");
	snd_inited = qtrue;
	return qtrue;
}

/*
===============
SNDDMA_GetDMAPos
===============
*/
int SNDDMA_GetDMAPos(void)
{
	return dmapos;
}

/*
===============
SNDDMA_Shutdown
===============
*/
void SNDDMA_Shutdown(void)
{
	Com_Printf("Closing SDL audio device...\n");
	SDL_PauseAudioDevice(dev);
	SDL_DestroyAudioStream(audioStream);
	audioStream = NULL;
	SDL_CloseAudioDevice(dev);
	dev = 0;
	SDL_QuitSubSystem(SDL_INIT_AUDIO);
	free(dma.buffer);
	dma.buffer = NULL;
	dmapos = dmasize = 0;
	snd_inited = qfalse;
	Com_Printf("SDL audio device shut down.\n");
}

/*
===============
SNDDMA_Submit

Send sound to device if buffer isn't really the dma buffer
===============
*/
void SNDDMA_Submit(void)
{
	SDL_UnlockAudioStream(audioStream);
}

/*
===============
SNDDMA_BeginPainting
===============
*/
void SNDDMA_BeginPainting (void)
{
	SDL_LockAudioStream(audioStream);
}

#ifdef USE_OPENAL
extern int s_UseOpenAL;
#endif

// (De)activates sound playback
void SNDDMA_Activate( qboolean activate )
{
#ifdef USE_OPENAL
	if ( s_UseOpenAL )
	{
		S_AL_MuteAllSounds( (qboolean)!activate );
	}
#endif

	if ( activate )
	{
		S_ClearSoundBuffer();
		SDL_ResumeAudioDevice(dev);
	}
	else
	{
		SDL_PauseAudioDevice(dev);
	}
}
