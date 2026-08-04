#ifndef BLE_SERVICE_H_
#define BLE_SERVICE_H_

#include <stddef.h>
#include <stdbool.h>
#include "watch_protocol.h"

/* caller_name is NUL-terminated, truncated to WATCH_CALL_EVENT_NAME_MAX_LEN;
 * the pointer is only valid for the duration of the callback.
 *
 * call_command and music_command have no callback here: per WatchProtocol,
 * both are watch -> phone notify-only characteristics (see
 * ble_service_notify_call_command / ble_service_notify_music_command below),
 * so there's nothing for the phone to write and nothing to callback on.
 */
typedef void (*ble_call_state_cb_t)(enum watch_call_state state, const char *caller_name);
typedef void (*ble_time_sync_cb_t)(const struct watch_time_sync_payload *sync);
typedef void (*ble_temperature_cb_t)(const struct watch_temperature_payload *temp);
typedef void (*ble_session_mode_cb_t)(enum watch_session_mode mode);

struct ble_service_callbacks {
	ble_call_state_cb_t on_call_state;
	ble_time_sync_cb_t on_time_sync;
	ble_temperature_cb_t on_temperature;
	ble_session_mode_cb_t on_session_mode;
};

/* Registers GATT write handlers; call once at boot before advertising. */
int ble_service_init(const struct ble_service_callbacks *callbacks);

int ble_service_start_advertising(void);
bool ble_service_is_connected(void);

/* Applies a connection parameter update matching the requested session
 * mode. This is the firmware side of the battery-life lever described in
 * GOALS.md — call it whenever the phone writes the session_mode
 * characteristic (see on_session_mode) or a local event (incoming call,
 * button press) requires tightening/loosening the link.
 */
int ble_service_apply_session_mode(enum watch_session_mode mode);

int ble_service_notify_call_state(enum watch_call_state state, const char *caller_name);
int ble_service_notify_call_command(enum watch_call_command cmd);
int ble_service_notify_music_command(enum watch_music_command cmd);
int ble_service_notify_button_event(enum watch_button_event event);

/* pcm must be raw PCM16 mono 16kHz samples; this prepends the
 * watch_audio_frame_header and fragments as needed for the negotiated MTU.
 */
int ble_service_notify_audio_frame(const uint8_t *pcm, size_t pcm_len);

int ble_service_notify_status(const struct watch_status_payload *status);

#endif /* BLE_SERVICE_H_ */
