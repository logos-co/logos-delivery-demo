cmake_minimum_required(VERSION 3.14)
project(LogosDeliveryDemoPlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

logos_module(
    NAME delivery_demo
    REP_FILE src/delivery_demo.rep
    SOURCES
        src/delivery_demo_interface.h
        src/delivery_demo_plugin.h
        src/delivery_demo_plugin.cpp
)
