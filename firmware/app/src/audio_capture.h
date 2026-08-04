#ifndef AUDIO_CAPTURE_H_
#define AUDIO_CAPTURE_H_

/* Starts the PDM mic and begins forwarding captured audio as BLE
 * notifications (see ble_service_notify_audio_frame). Call on
 * talkStart/holdStart; stop on talkEnd/holdEnd. Safe to call repeatedly —
 * a start while already running, or a stop while already stopped, is a
 * no-op.
 */
int audio_capture_start(void);
int audio_capture_stop(void);

#endif /* AUDIO_CAPTURE_H_ */
