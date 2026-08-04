/*
 * C mirror of ios/CasioAI/Bluetooth/WatchProtocol.swift. This is the same
 * contract from the firmware side — UUIDs, enum values, and struct layouts
 * must match exactly. If you change one side, change both.
 *
 * nRF52832 is little-endian ARM Cortex-M4, matching the phone side's
 * explicit .littleEndian encoding, so packed multi-byte fields need no
 * manual byte-swapping here.
 */
#ifndef WATCH_PROTOCOL_H_
#define WATCH_PROTOCOL_H_

#include <stdint.h>
#include <zephyr/bluetooth/uuid.h>
#include <zephyr/sys/util.h>
#include <zephyr/toolchain.h>

/* ---- Service ---- */
#define BT_UUID_CASIOAI_SERVICE_VAL \
	BT_UUID_128_ENCODE(0x6a58e000, 0x0001, 0x4000, 0x8000, 0x00805f9b34fb)
#define BT_UUID_CASIOAI_SERVICE BT_UUID_DECLARE_128(BT_UUID_CASIOAI_SERVICE_VAL)

/* ---- Characteristics ---- */
#define BT_UUID_CASIOAI_CALL_STATE_VAL \
	BT_UUID_128_ENCODE(0x6a58e000, 0x0010, 0x4000, 0x8000, 0x00805f9b34fb)
#define BT_UUID_CASIOAI_CALL_STATE BT_UUID_DECLARE_128(BT_UUID_CASIOAI_CALL_STATE_VAL)

#define BT_UUID_CASIOAI_CALL_COMMAND_VAL \
	BT_UUID_128_ENCODE(0x6a58e000, 0x0011, 0x4000, 0x8000, 0x00805f9b34fb)
#define BT_UUID_CASIOAI_CALL_COMMAND BT_UUID_DECLARE_128(BT_UUID_CASIOAI_CALL_COMMAND_VAL)

#define BT_UUID_CASIOAI_MUSIC_COMMAND_VAL \
	BT_UUID_128_ENCODE(0x6a58e000, 0x0020, 0x4000, 0x8000, 0x00805f9b34fb)
#define BT_UUID_CASIOAI_MUSIC_COMMAND BT_UUID_DECLARE_128(BT_UUID_CASIOAI_MUSIC_COMMAND_VAL)

#define BT_UUID_CASIOAI_TIME_SYNC_VAL \
	BT_UUID_128_ENCODE(0x6a58e000, 0x0030, 0x4000, 0x8000, 0x00805f9b34fb)
#define BT_UUID_CASIOAI_TIME_SYNC BT_UUID_DECLARE_128(BT_UUID_CASIOAI_TIME_SYNC_VAL)

#define BT_UUID_CASIOAI_TEMPERATURE_VAL \
	BT_UUID_128_ENCODE(0x6a58e000, 0x0031, 0x4000, 0x8000, 0x00805f9b34fb)
#define BT_UUID_CASIOAI_TEMPERATURE BT_UUID_DECLARE_128(BT_UUID_CASIOAI_TEMPERATURE_VAL)

#define BT_UUID_CASIOAI_BUTTON_EVENT_VAL \
	BT_UUID_128_ENCODE(0x6a58e000, 0x0040, 0x4000, 0x8000, 0x00805f9b34fb)
#define BT_UUID_CASIOAI_BUTTON_EVENT BT_UUID_DECLARE_128(BT_UUID_CASIOAI_BUTTON_EVENT_VAL)

#define BT_UUID_CASIOAI_AUDIO_STREAM_VAL \
	BT_UUID_128_ENCODE(0x6a58e000, 0x0050, 0x4000, 0x8000, 0x00805f9b34fb)
#define BT_UUID_CASIOAI_AUDIO_STREAM BT_UUID_DECLARE_128(BT_UUID_CASIOAI_AUDIO_STREAM_VAL)

#define BT_UUID_CASIOAI_STATUS_VAL \
	BT_UUID_128_ENCODE(0x6a58e000, 0x0060, 0x4000, 0x8000, 0x00805f9b34fb)
#define BT_UUID_CASIOAI_STATUS BT_UUID_DECLARE_128(BT_UUID_CASIOAI_STATUS_VAL)

#define BT_UUID_CASIOAI_SESSION_MODE_VAL \
	BT_UUID_128_ENCODE(0x6a58e000, 0x0070, 0x4000, 0x8000, 0x00805f9b34fb)
#define BT_UUID_CASIOAI_SESSION_MODE BT_UUID_DECLARE_128(BT_UUID_CASIOAI_SESSION_MODE_VAL)

/* ---- Enums (values must match WatchProtocol.swift's raw values) ---- */

enum watch_call_state {
	WATCH_CALL_STATE_IDLE = 0,
	WATCH_CALL_STATE_INCOMING = 1,
	WATCH_CALL_STATE_ACTIVE = 2,
};

enum watch_call_command {
	WATCH_CALL_CMD_ANSWER = 0,
	WATCH_CALL_CMD_REJECT = 1,
};

enum watch_music_command {
	WATCH_MUSIC_CMD_PLAY_PAUSE = 0,
	WATCH_MUSIC_CMD_NEXT = 1,
	WATCH_MUSIC_CMD_PREVIOUS = 2,
	WATCH_MUSIC_CMD_VOLUME_UP = 3,
	WATCH_MUSIC_CMD_VOLUME_DOWN = 4,
};

enum watch_button_event {
	WATCH_BUTTON_TALK_START = 0,
	WATCH_BUTTON_TALK_END = 1,
	WATCH_BUTTON_HOLD_START = 2,
	WATCH_BUTTON_HOLD_END = 3,
};

enum watch_session_mode {
	WATCH_SESSION_IDLE = 0,
	WATCH_SESSION_ACTIVE = 1,
};

#define WATCH_STATUS_FLAG_CHARGING      BIT(0)
#define WATCH_STATUS_FLAG_LOW_BATTERY   BIT(1)
#define WATCH_STATUS_FLAG_ALARM_VIBRATE BIT(2)
#define WATCH_STATUS_FLAG_ALARM_BEEP    BIT(3)

#define WATCH_AUDIO_FORMAT_PCM16_MONO_16K 1
#define WATCH_CALL_EVENT_NAME_MAX_LEN     32

/* ---- Wire structs (packed — these are the exact BLE payload layouts) ---- */

struct __packed watch_status_payload {
	uint8_t battery_percent; /* 0-100 */
	uint8_t flags;           /* WATCH_STATUS_FLAG_* bitmask */
	uint8_t firmware_version;
};

struct __packed watch_time_sync_payload {
	int64_t unix_seconds;         /* LE, matches phone's .littleEndian encoding */
	int8_t utc_offset_quarter_hours;
};

struct __packed watch_temperature_payload {
	int8_t low_fahrenheit;
	int8_t high_fahrenheit;
};

struct __packed watch_audio_frame_header {
	uint8_t format; /* WATCH_AUDIO_FORMAT_* */
	uint16_t sequence;
};

#endif /* WATCH_PROTOCOL_H_ */
