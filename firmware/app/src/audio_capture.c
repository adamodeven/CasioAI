/*
 * PDM mic capture via nrfx directly (not Zephyr's higher-level audio/dmic
 * subsystem — that's oriented around larger, more general audio pipelines
 * than "stream mono 16kHz PCM to BLE," and going straight to nrfx keeps
 * this close to what a battery-constrained wearable actually needs:
 * EasyDMA-driven capture with the CPU only waking up once per buffer).
 *
 * nrfx_pdm's event-handler struct shape has changed across nrfx versions;
 * this targets the request/release double-buffer pattern
 * (`buffer_requested` / `buffer_released` fields on nrfx_pdm_evt_t) used by
 * nrfx v2/v3. Check nrfx_pdm.h in your installed NCS if this doesn't match —
 * flagged in firmware/README.md as one of the higher-risk files.
 */
#include <nrfx_pdm.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/sys/util.h>

#include "audio_capture.h"
#include "ble_service.h"
#include "watch_protocol.h"

LOG_MODULE_REGISTER(audio_capture, LOG_LEVEL_INF);

/* 256 samples @ 16kHz = 16ms per buffer; double-buffered so nrfx always has
 * a free buffer to fill while the other is being forwarded over BLE.
 */
#define PDM_BUFFER_SAMPLES 256
/* PCM bytes per BLE notification payload, sized for the 20-byte ATT MTU
 * floor minus the 3-byte watch_audio_frame_header (see ble_service.c's
 * note on negotiating a larger MTU instead of hardcoding this).
 */
#define AUDIO_BLE_CHUNK_BYTES 17

static int16_t pdm_buf[2][PDM_BUFFER_SAMPLES];
static uint8_t next_buf_idx;
static volatile bool capture_active;

static struct k_work forward_work;
static const int16_t *pending_buffer;
static size_t pending_samples;

static void forward_work_handler(struct k_work *work)
{
	ARG_UNUSED(work);

	const uint8_t *bytes = (const uint8_t *)pending_buffer;
	size_t total_bytes = pending_samples * sizeof(int16_t);
	size_t offset = 0;

	while (offset < total_bytes) {
		size_t chunk = MIN((size_t)AUDIO_BLE_CHUNK_BYTES, total_bytes - offset);
		ble_service_notify_audio_frame(bytes + offset, chunk);
		offset += chunk;
	}
}

static void pdm_event_handler(nrfx_pdm_evt_t const *evt)
{
	if (evt->error != NRFX_PDM_NO_ERROR) {
		LOG_WRN("PDM error %d", evt->error);
	}

	if (evt->buffer_requested && capture_active) {
		nrfx_pdm_buffer_set(pdm_buf[next_buf_idx], PDM_BUFFER_SAMPLES);
		next_buf_idx ^= 1;
	}

	if (evt->buffer_released != NULL) {
		/* Runs in nrfx's ISR context — hand off to the system
		 * workqueue rather than calling into the BLE stack here.
		 * Double-buffering gives a full buffer period (~16ms) of
		 * margin before this memory is reused, which is comfortably
		 * more than bt_gatt_notify() needs to drain it.
		 */
		pending_buffer = evt->buffer_released;
		pending_samples = evt->buffer_released_size;
		k_work_submit(&forward_work);
	}
}

int audio_capture_start(void)
{
	if (capture_active) {
		return 0;
	}

	static bool pdm_initialized;
	if (!pdm_initialized) {
		k_work_init(&forward_work, forward_work_handler);

		nrfx_pdm_config_t config = NRFX_PDM_DEFAULT_CONFIG(
			NRF_GPIO_PIN_MAP(0, 2) /* PDM CLK, see PINMAP.md */,
			NRF_GPIO_PIN_MAP(0, 3) /* PDM DIN */);
		config.mode = NRFX_PDM_MODE_MONO;
		config.clock_freq = NRF_PDM_FREQ_1032K; /* -> ~16kHz output rate */

		nrfx_err_t err = nrfx_pdm_init(&config, pdm_event_handler);
		if (err != NRFX_SUCCESS) {
			LOG_ERR("nrfx_pdm_init failed (0x%x)", err);
			return -EIO;
		}
		pdm_initialized = true;
	}

	next_buf_idx = 0;
	capture_active = true;

	nrfx_err_t err = nrfx_pdm_start();
	if (err != NRFX_SUCCESS) {
		LOG_ERR("nrfx_pdm_start failed (0x%x)", err);
		capture_active = false;
		return -EIO;
	}

	return 0;
}

int audio_capture_stop(void)
{
	if (!capture_active) {
		return 0;
	}
	capture_active = false;
	nrfx_pdm_stop();
	return 0;
}
