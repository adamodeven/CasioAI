cmake_minimum_required(VERSION 3.20.0)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(casioai_watch)

target_sources(app PRIVATE
    src/main.c
    src/ble_service.c
    src/buttons.c
    src/audio_capture.c
    src/lcd_driver.c
    src/haptics.c
    src/power.c
)

target_include_directories(app PRIVATE src)
