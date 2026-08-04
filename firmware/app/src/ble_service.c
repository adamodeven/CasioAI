/*
 * GATT service implementing the WatchProtocol contract (watch_protocol.h).
 *
 * The attribute-index enum below must stay in the same order as the
 * BT_GATT_SERVICE_DEFINE table — that's how Zephyr's bt_gatt_notify() finds
 * a characteristic's value attribute (`&casioai_svc.attrs[N]`), and nothing
 * checks it for you at the macro level. The BUILD_ASSERT at the bottom of
 * this file is a real (compile-time) safety net for that, not decoration —
 * if the two drift apart it'll fail to build rather than notify the wrong
 * characteristic at runtime.
 */
#include <string.h>
#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/conn.h>
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/bluetooth/hci.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include "ble_service.h"

LOG_MODULE_REGISTER(ble_service, LOG_LEVEL_INF);

static struct ble_service_callbacks cbs;
static struct bt_conn *current_conn;
static uint16_t audio_sequence;

static bool call_command_notify_enabled;
static bool music_command_notify_enabled;
static bool button_event_indicate_enabled;
static bool audio_stream_notify_enabled;
static bool status_notify_enabled;

static struct watch_status_payload latest_status;

/* Idle: loose interval + high slave latency for lowest average current.
 * 400-800 * 1.25ms = 500-1000ms interval, latency 4, 4000ms supervision
 * timeout. Starting point only — tune against real current-draw
 * measurements toward the 3-6 month CR2016 target.
 */
static const struct bt_le_conn_param conn_param_idle = BT_LE_CONN_PARAM_INIT(400, 800, 4, 400);

/* Active: tight interval for low-latency audio/button response.
 * 12-24 * 1.25ms = 15-30ms interval, latency 0, 4000ms timeout.
 */
static const struct bt_le_conn_param conn_param_active = BT_LE_CONN_PARAM_INIT(12, 24, 0, 400);

enum casioai_attr_index {
	ATTR_IDX_SVC = 0,
	ATTR_IDX_CALL_STATE_CHRC,
	ATTR_IDX_CALL_STATE_VALUE,
	ATTR_IDX_CALL_COMMAND_CHRC,
	ATTR_IDX_CALL_COMMAND_VALUE,
	ATTR_IDX_CALL_COMMAND_CCC,
	ATTR_IDX_MUSIC_COMMAND_CHRC,
	ATTR_IDX_MUSIC_COMMAND_VALUE,
	ATTR_IDX_MUSIC_COMMAND_CCC,
	ATTR_IDX_TIME_SYNC_CHRC,
	ATTR_IDX_TIME_SYNC_VALUE,
	ATTR_IDX_TEMPERATURE_CHRC,
	ATTR_IDX_TEMPERATURE_VALUE,
	ATTR_IDX_BUTTON_EVENT_CHRC,
	ATTR_IDX_BUTTON_EVENT_VALUE,
	ATTR_IDX_BUTTON_EVENT_CCC,
	ATTR_IDX_AUDIO_STREAM_CHRC,
	ATTR_IDX_AUDIO_STREAM_VALUE,
	ATTR_IDX_AUDIO_STREAM_CCC,
	ATTR_IDX_STATUS_CHRC,
	ATTR_IDX_STATUS_VALUE,
	ATTR_IDX_STATUS_CCC,
	ATTR_IDX_SESSION_MODE_CHRC,
	ATTR_IDX_SESSION_MODE_VALUE,
	ATTR_IDX_COUNT,
};

/* ---- CCC change handlers ---- */

static void call_command_ccc_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
	call_command_notify_enabled = (value == BT_GATT_CCC_NOTIFY);
}

static void music_command_ccc_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
	music_command_notify_enabled = (value == BT_GATT_CCC_NOTIFY);
}

static void button_event_ccc_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
	button_event_indicate_enabled = (value == BT_GATT_CCC_INDICATE);
}

static void audio_stream_ccc_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
	audio_stream_notify_enabled = (value == BT_GATT_CCC_NOTIFY);
}

static void status_ccc_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
	status_notify_enabled = (value == BT_GATT_CCC_NOTIFY);
}

/* ---- Write handlers ---- */

static ssize_t write_call_state(struct bt_conn *conn, const struct bt_gatt_attr *attr,
				 const void *buf, uint16_t len, uint16_t offset, uint8_t flags)
{
	ARG_UNUSED(conn);
	ARG_UNUSED(attr);
	ARG_UNUSED(offset);
	ARG_UNUSED(flags);

	/* Payload: 1 state byte + up to WATCH_CALL_EVENT_NAME_MAX_LEN bytes of
	 * UTF-8 caller name (see WatchProtocol.CallEvent.encoded on the phone
	 * side) — variable length, so only the minimum 1-byte state is
	 * required.
	 */
	if (len < 1 || len > 1 + WATCH_CALL_EVENT_NAME_MAX_LEN) {
		return BT_GATT_ERR(BT_ATT_ERR_INVALID_ATTRIBUTE_LEN);
	}

	const uint8_t *bytes = buf;
	enum watch_call_state state = (enum watch_call_state)bytes[0];

	char name[WATCH_CALL_EVENT_NAME_MAX_LEN + 1] = {0};
	size_t name_len = len - 1;
	if (name_len) {
		memcpy(name, &bytes[1], name_len);
	}
	name[name_len] = '\0';

	if (cbs.on_call_state) {
		cbs.on_call_state(state, name);
	}
	return len;
}

static ssize_t write_time_sync(struct bt_conn *conn, const struct bt_gatt_attr *attr,
				const void *buf, uint16_t len, uint16_t offset, uint8_t flags)
{
	ARG_UNUSED(conn);
	ARG_UNUSED(attr);
	ARG_UNUSED(offset);
	ARG_UNUSED(flags);

	if (len != sizeof(struct watch_time_sync_payload)) {
		return BT_GATT_ERR(BT_ATT_ERR_INVALID_ATTRIBUTE_LEN);
	}

	if (cbs.on_time_sync) {
		cbs.on_time_sync((const struct watch_time_sync_payload *)buf);
	}
	return len;
}

static ssize_t write_temperature(struct bt_conn *conn, const struct bt_gatt_attr *attr,
				  const void *buf, uint16_t len, uint16_t offset, uint8_t flags)
{
	ARG_UNUSED(conn);
	ARG_UNUSED(attr);
	ARG_UNUSED(offset);
	ARG_UNUSED(flags);

	if (len != sizeof(struct watch_temperature_payload)) {
		return BT_GATT_ERR(BT_ATT_ERR_INVALID_ATTRIBUTE_LEN);
	}

	if (cbs.on_temperature) {
		cbs.on_temperature((const struct watch_temperature_payload *)buf);
	}
	return len;
}

static ssize_t write_session_mode(struct bt_conn *conn, const struct bt_gatt_attr *attr,
				   const void *buf, uint16_t len, uint16_t offset, uint8_t flags)
{
	ARG_UNUSED(attr);
	ARG_UNUSED(offset);
	ARG_UNUSED(flags);

	if (len != 1) {
		return BT_GATT_ERR(BT_ATT_ERR_INVALID_ATTRIBUTE_LEN);
	}

	enum watch_session_mode mode = (enum watch_session_mode)((const uint8_t *)buf)[0];
	ble_service_apply_session_mode(mode);
	if (cbs.on_session_mode) {
		cbs.on_session_mode(mode);
	}
	return len;
}

static ssize_t read_status(struct bt_conn *conn, const struct bt_gatt_attr *attr, void *buf,
			    uint16_t len, uint16_t offset)
{
	return bt_gatt_attr_read(conn, attr, buf, len, offset, &latest_status,
				  sizeof(latest_status));
}

/* watch_call_command / watch_music_command have no phone->watch write path
 * in this design (they're watch->phone notifications only), so no write
 * handler is registered for those two.
 */

BT_GATT_SERVICE_DEFINE(
	casioai_svc, BT_GATT_PRIMARY_SERVICE(BT_UUID_CASIOAI_SERVICE),

	BT_GATT_CHARACTERISTIC(BT_UUID_CASIOAI_CALL_STATE, BT_GATT_CHRC_WRITE,
				BT_GATT_PERM_WRITE, NULL, write_call_state, NULL),

	BT_GATT_CHARACTERISTIC(BT_UUID_CASIOAI_CALL_COMMAND, BT_GATT_CHRC_NOTIFY,
				BT_GATT_PERM_NONE, NULL, NULL, NULL),
	BT_GATT_CCC(call_command_ccc_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),

	BT_GATT_CHARACTERISTIC(BT_UUID_CASIOAI_MUSIC_COMMAND, BT_GATT_CHRC_NOTIFY,
				BT_GATT_PERM_NONE, NULL, NULL, NULL),
	BT_GATT_CCC(music_command_ccc_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),

	BT_GATT_CHARACTERISTIC(BT_UUID_CASIOAI_TIME_SYNC, BT_GATT_CHRC_WRITE_WITHOUT_RESP,
				BT_GATT_PERM_WRITE, NULL, write_time_sync, NULL),

	BT_GATT_CHARACTERISTIC(BT_UUID_CASIOAI_TEMPERATURE, BT_GATT_CHRC_WRITE_WITHOUT_RESP,
				BT_GATT_PERM_WRITE, NULL, write_temperature, NULL),

	BT_GATT_CHARACTERISTIC(BT_UUID_CASIOAI_BUTTON_EVENT, BT_GATT_CHRC_INDICATE,
				BT_GATT_PERM_NONE, NULL, NULL, NULL),
	BT_GATT_CCC(button_event_ccc_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),

	BT_GATT_CHARACTERISTIC(BT_UUID_CASIOAI_AUDIO_STREAM, BT_GATT_CHRC_NOTIFY,
				BT_GATT_PERM_NONE, NULL, NULL, NULL),
	BT_GATT_CCC(audio_stream_ccc_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),

	BT_GATT_CHARACTERISTIC(BT_UUID_CASIOAI_STATUS, BT_GATT_CHRC_READ | BT_GATT_CHRC_NOTIFY,
				BT_GATT_PERM_READ, read_status, NULL, NULL),
	BT_GATT_CCC(status_ccc_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),

	BT_GATT_CHARACTERISTIC(BT_UUID_CASIOAI_SESSION_MODE, BT_GATT_CHRC_WRITE_WITHOUT_RESP,
				BT_GATT_PERM_WRITE, NULL, write_session_mode, NULL), );

BUILD_ASSERT(ATTR_IDX_COUNT == ARRAY_SIZE(casioai_svc.attrs),
	     "casioai_attr_index enum is out of sync with BT_GATT_SERVICE_DEFINE - "
	     "notify calls would hit the wrong characteristic");

/* ---- Advertising ---- */

static const struct bt_data ad[] = {
	BT_DATA_BYTES(BT_DATA_FLAGS, (BT_LE_AD_GENERAL | BT_LE_AD_NO_BREDR)),
	BT_DATA_BYTES(BT_DATA_UUID128_ALL, BT_UUID_CASIOAI_SERVICE_VAL),
};

static const struct bt_data sd[] = {
	BT_DATA(BT_DATA_NAME_COMPLETE, CONFIG_BT_DEVICE_NAME, sizeof(CONFIG_BT_DEVICE_NAME) - 1),
};

static void on_connected(struct bt_conn *conn, uint8_t err)
{
	if (err) {
		LOG_WRN("Connection failed (err %u)", err);
		return;
	}
	LOG_INF("Connected");
	current_conn = bt_conn_ref(conn);
	/* Start loose; ble_service_apply_session_mode() tightens on demand. */
	ble_service_apply_session_mode(WATCH_SESSION_IDLE);
}

static void on_disconnected(struct bt_conn *conn, uint8_t reason)
{
	LOG_INF("Disconnected (reason %u)", reason);
	if (current_conn) {
		bt_conn_unref(current_conn);
		current_conn = NULL;
	}
	ble_service_start_advertising();
}

static struct bt_conn_cb conn_callbacks = {
	.connected = on_connected,
	.disconnected = on_disconnected,
};

int ble_service_init(const struct ble_service_callbacks *callbacks)
{
	if (callbacks) {
		cbs = *callbacks;
	}

	int err = bt_enable(NULL);
	if (err) {
		LOG_ERR("bt_enable failed (%d)", err);
		return err;
	}

	bt_conn_cb_register(&conn_callbacks);
	return 0;
}

int ble_service_start_advertising(void)
{
	return bt_le_adv_start(BT_LE_ADV_CONN_NAME, ad, ARRAY_SIZE(ad), sd, ARRAY_SIZE(sd));
}

bool ble_service_is_connected(void)
{
	return current_conn != NULL;
}

int ble_service_apply_session_mode(enum watch_session_mode mode)
{
	if (!current_conn) {
		return -ENOTCONN;
	}
	const struct bt_le_conn_param *param =
		(mode == WATCH_SESSION_ACTIVE) ? &conn_param_active : &conn_param_idle;
	return bt_conn_le_param_update(current_conn, param);
}

int ble_service_notify_call_state(enum watch_call_state state, const char *caller_name)
{
	if (!current_conn) {
		return -ENOTCONN;
	}

	uint8_t payload[1 + WATCH_CALL_EVENT_NAME_MAX_LEN];
	size_t name_len = 0;

	payload[0] = (uint8_t)state;
	if (caller_name) {
		name_len = strnlen(caller_name, WATCH_CALL_EVENT_NAME_MAX_LEN);
		memcpy(&payload[1], caller_name, name_len);
	}

	return bt_gatt_notify(current_conn, &casioai_svc.attrs[ATTR_IDX_CALL_STATE_VALUE], payload,
			       1 + name_len);
}

int ble_service_notify_call_command(enum watch_call_command cmd)
{
	if (!current_conn || !call_command_notify_enabled) {
		return -ENOTCONN;
	}
	uint8_t value = (uint8_t)cmd;
	return bt_gatt_notify(current_conn, &casioai_svc.attrs[ATTR_IDX_CALL_COMMAND_VALUE], &value,
			       sizeof(value));
}

int ble_service_notify_music_command(enum watch_music_command cmd)
{
	if (!current_conn || !music_command_notify_enabled) {
		return -ENOTCONN;
	}
	uint8_t value = (uint8_t)cmd;
	return bt_gatt_notify(current_conn, &casioai_svc.attrs[ATTR_IDX_MUSIC_COMMAND_VALUE],
			       &value, sizeof(value));
}

int ble_service_notify_button_event(enum watch_button_event event)
{
	if (!current_conn || !button_event_indicate_enabled) {
		return -ENOTCONN;
	}
	uint8_t value = (uint8_t)event;
	return bt_gatt_notify(current_conn, &casioai_svc.attrs[ATTR_IDX_BUTTON_EVENT_VALUE],
			       &value, sizeof(value));
}

int ble_service_notify_audio_frame(const uint8_t *pcm, size_t pcm_len)
{
	if (!current_conn || !audio_stream_notify_enabled) {
		return -ENOTCONN;
	}

	/* ATT_MTU is negotiated per-connection; 20 bytes is the guaranteed
	 * minimum payload without an MTU exchange. Real firmware should
	 * request a larger MTU during connection setup and size this buffer
	 * from bt_gatt_get_mtu() instead of hardcoding the floor.
	 */
	uint8_t frame[20];
	struct watch_audio_frame_header header = {
		.format = WATCH_AUDIO_FORMAT_PCM16_MONO_16K,
		.sequence = audio_sequence++,
	};
	size_t header_len = sizeof(header);
	size_t chunk = MIN(pcm_len, sizeof(frame) - header_len);

	memcpy(frame, &header, header_len);
	memcpy(frame + header_len, pcm, chunk);

	return bt_gatt_notify(current_conn, &casioai_svc.attrs[ATTR_IDX_AUDIO_STREAM_VALUE], frame,
			       header_len + chunk);
}

int ble_service_notify_status(const struct watch_status_payload *status)
{
	latest_status = *status;

	if (!current_conn || !status_notify_enabled) {
		return -ENOTCONN;
	}
	return bt_gatt_notify(current_conn, &casioai_svc.attrs[ATTR_IDX_STATUS_VALUE], status,
			       sizeof(*status));
}
