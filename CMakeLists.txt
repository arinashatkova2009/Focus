cmake_minimum_required(VERSION 3.21)
project(focus VERSION 1.0 LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
find_package(Qt6 6.10 REQUIRED COMPONENTS Quick QuickControls2 Network Multimedia ShaderTools QuickDialogs2)
qt_standard_project_setup(REQUIRES 6.10)
qt_add_executable(appfocus main.cpp FocusBackend.cpp FocusBackend.h)
qt_add_qml_module(appfocus URI focus VERSION 1.0 NO_CACHEGEN QML_FILES Main.qml WorkspacePage.qml)
qt_add_shaders(appfocus welcome_glass
    PREFIX "/focus" FILES shaders/glass-title.frag)
target_link_libraries(appfocus PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::Network Qt6::Multimedia Qt6::QuickDialogs2)
target_compile_definitions(appfocus PRIVATE FOCUS_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
set_target_properties(appfocus PROPERTIES WIN32_EXECUTABLE TRUE MACOSX_BUNDLE TRUE)
if(MSVC)
    target_compile_options(appfocus PRIVATE /utf-8)
endif()
add_custom_target(focus_runtime ALL
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${CMAKE_CURRENT_SOURCE_DIR}/backend" "$<TARGET_FILE_DIR:appfocus>/backend"
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${CMAKE_CURRENT_SOURCE_DIR}/runtime" "$<TARGET_FILE_DIR:appfocus>/runtime"
    COMMENT "Copying Focus backend and portable Python"
)
add_dependencies(appfocus focus_runtime)
include(GNUInstallDirs)
install(TARGETS appfocus BUNDLE DESTINATION . RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(DIRECTORY backend runtime DESTINATION ${CMAKE_INSTALL_BINDIR} PATTERN "__pycache__" EXCLUDE)

option(FOCUS_BUILD_TESTS "Build the isolated Qt integration test" OFF)
if(FOCUS_BUILD_TESTS)
    find_package(Qt6 REQUIRED COMPONENTS Test)
    qt_add_executable(focus_gui_test tests/gui_smoke.cpp FocusBackend.cpp FocusBackend.h)
    qt_add_qml_module(focus_gui_test URI focus VERSION 1.0 NO_CACHEGEN QML_FILES Main.qml WorkspacePage.qml
        OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/test-focus")
    qt_add_shaders(focus_gui_test test_welcome_glass
        PREFIX "/focus" FILES shaders/glass-title.frag)
    target_include_directories(focus_gui_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
    target_compile_definitions(focus_gui_test PRIVATE FOCUS_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
    target_link_libraries(focus_gui_test PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::Network Qt6::Multimedia Qt6::QuickDialogs2 Qt6::Test)
    if(MSVC)
        target_compile_options(focus_gui_test PRIVATE /utf-8)
    endif()
endif()
