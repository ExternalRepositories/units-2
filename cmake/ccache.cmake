# The MIT License (MIT)
#
# Copyright (c) 2017 Mateusz Pusz
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

cmake_minimum_required(VERSION 3.4)

include(modern_project_structure)

macro(_enable_ccache)
    set(_options ACCOUNT_FOR_COMPILE_TIME_HEADER_CHANGES ACCOUNT_FOR_PCH ACCOUNT_FOR_MODULES)
    set(_one_value_args MODE BASE_DIR)
    set(_multi_value_args PREFIXES)
    cmake_parse_arguments(PARSE_ARGV 0 _enable_ccache "${_options}" "${_one_value_args}" "${_multi_value_args}")

    if(NOT CMAKE_CURRENT_SOURCE_DIR STREQUAL CMAKE_SOURCE_DIR)
        message(FATAL_ERROR "'enable_ccache' function should be called from the top-level CMakeLists.txt file!")
        # otherwise, it will not work for XCode
        return()
    endif()

    set(_ccacheEnv
        CCACHE_CPP2=1 # avoids spurious warnings with some compilers for ccache older than 3.3
        # CCACHE_ABSSTDERR=1 # reverts absolute paths after applying CCACHE_BASEDIR
    )

    # validate and process arguments
    if(_enable_ccache_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "Invalid arguments '${_enable_ccache_UNPARSED_ARGUMENTS}'")
    endif()

    if(_enable_ccache_KEYWORDS_MISSING_VALUES)
        message(FATAL_ERROR "No value provided for '${_enable_ccache_KEYWORDS_MISSING_VALUES}'")
    endif()

    if(_enable_ccache_MODE)
        set(_valid_mode_values DIRECT_PREPROCESSOR DIRECT_DEPEND PREPROCESSOR DEPEND)
        if(NOT _enable_ccache_MODE IN_LIST _valid_mode_values)
            message(FATAL_ERROR "'MODE' should be one of ${_valid_mode_values}")
        endif()
    endif()
        
    if(_enable_ccache_MODE STREQUAL DIRECT_DEPEND)
        list(APPEND _ccacheEnv CCACHE_DIRECT=1 CCACHE_DEPEND=1)
    elseif(_enable_ccache_MODE STREQUAL PREPROCESSOR)
        list(APPEND _ccacheEnv CCACHE_NO_DIRECT=1 CCACHE_NO_DEPEND=1)
    elseif(_enable_ccache_MODE STREQUAL DEPEND)
        list(APPEND _ccacheEnv CCACHE_NO_DIRECT=1 CCACHE_DEPEND=1)
    else()
        set(_enable_ccache_MODE DIRECT_PREPROCESSOR)
        list(APPEND _ccacheEnv CCACHE_DIRECT=1 CCACHE_NO_DEPEND=1)
    endif()

    if(_enable_ccache_BASE_DIR)
        if(NOT EXISTS ${_enable_ccache_BASE_DIR})
            message(FATAL_ERROR "Base directory '${_enable_ccache_BASE_DIR}' does not exist")
        endif()
        list(APPEND _ccacheEnv "CCACHE_BASEDIR=${_enable_ccache_BASE_DIR}")
    else()
        list(APPEND _ccacheEnv "CCACHE_BASEDIR=${CMAKE_SOURCE_DIR}")
    endif()

    if(_enable_ccache_PREFIXES)
        string(REPLACE ";" " " _prefixes_txt "${_enable_ccache_PREFIXES}")
        list(APPEND _ccacheEnv "CCACHE_PREFIX=${_prefixes_txt}")
    endif()

    if(_enable_ccache_ACCOUNT_FOR_COMPILE_TIME_HEADER_CHANGES)
        list(APPEND _sloppiness include_file_mtime include_file_ctime)
    endif()

    if(_enable_ccache_ACCOUNT_FOR_PCH)
        list(APPEND _sloppiness pch_defines time_macros include_file_mtime include_file_ctime)
    endif()

    if(_enable_ccache_ACCOUNT_FOR_MODULES)
        if(NOT _enable_ccache_MODE STREQUAL DIRECT_DEPEND)
            message(FATAL_ERROR "DIRECT_DEPEND mode required with ACCOUNT_FOR_MODULES option")
        endif()
        list(APPEND _sloppiness modules)
    endif()

    if(_sloppiness)
        list(REMOVE_DUPLICATES _sloppiness)
        string(REPLACE ";" "," _sloppiness_txt "${_sloppiness}")
        list(APPEND _ccacheEnv "CCACHE_SLOPPINESS=${_sloppiness_txt}")
    endif()

    message(STATUS "Enabling ccache with '${_ccacheEnv}'")

    if(CMAKE_GENERATOR MATCHES "Ninja|Makefiles")
        foreach(_lang IN ITEMS C CXX OBJC OBJCXX CUDA)
            set(CMAKE_${_lang}_COMPILER_LAUNCHER
                ${CMAKE_COMMAND} -E env
                ${_ccacheEnv} ${_ccache_path}
                PARENT_SCOPE
            )
        endforeach()
    elseif(CMAKE_GENERATOR STREQUAL Xcode)
        # Each of the Xcode project variables allow specifying only a single value, but the ccache command line needs to have multiple options.
        # A separate launch script needs to be written out and the project variables pointed at them.
        foreach(_lang IN ITEMS C CXX)
        set(launch${_lang} ${CMAKE_BINARY_DIR}/launch-${_lang})
        file(WRITE ${launch${_lang}} "#!/bin/bash\n\n")
        foreach(keyVal IN LISTS _ccacheEnv)
            file(APPEND ${launch${_lang}} "export ${keyVal}\n")
        endforeach()
            file(APPEND ${launch${_lang}}
                "exec \"${CCACHE_PROGRAM}\" "
                "\"${CMAKE_${_lang}_COMPILER}\" \"$@\"\n"
            )
            execute_process(COMMAND chmod a+rx ${launch${_lang}})
        endforeach()
        set(CMAKE_XCODE_ATTRIBUTE_CC ${launchC} PARENT_SCOPE)
        set(CMAKE_XCODE_ATTRIBUTE_CXX ${launchCXX} PARENT_SCOPE)
        set(CMAKE_XCODE_ATTRIBUTE_LD ${launchC} PARENT_SCOPE)
        set(CMAKE_XCODE_ATTRIBUTE_LDPLUSPLUS ${launchCXX} PARENT_SCOPE)
    else()
        message(WARNING "'${CMAKE_GENERATOR}' generator is not supported by ccache!")
        return()
    endif()
endmacro()


#
# enable_ccache([MODE DIRECT_PREPROCESSOR|DIRECT_DEPEND|PREPROCESSOR|DEPEND] # DIRECT_PREPROCESSOR by default
#               [BASE_DIR dir]                                               # ${CMAKE_SOURCE_DIR} by default
#               [ACCOUNT_FOR_COMPILE_TIME_HEADER_CHANGES]
#               [ACCOUNT_FOR_PCH]
#               [ACCOUNT_FOR_MODULES]
#               [PREFIXES prefixes...])
# 
# BASE_DIR
# Set this option to ${CMAKE_BINARY_DIR} if you use FetchContent a lot for many projects with the same build options.
# Otherwise, if most of the sources come from the project itself then the default ${CMAKE_SOURCE_DIR} may be
# a better choice.
# 
# ACCOUNT_FOR_COMPILE_TIME_HEADER_CHANGES
# Use it if some header files are being generated by the compilation process.
# 
# ACCOUNT_FOR_PCH
# Use it if precompiled headers are enabled in your project. Automatically includes uses
# ACCOUNT_FOR_COMPILE_TIME_HEADER_CHANGES as well.
# See here for details: https://ccache.dev/manual/4.2.1.html#_precompiled_headers
# 
# ACCOUNT_FOR_MODULES
# Use it for projects with C++20 modules. Requires DIRECT_DEPEND mode.
#
# PREFIXES
# A list of other tools that should be used together with ccache as a compiler launcher
# (i.e. distcc, icecc, sccache-dist, ...).
# 
function(enable_ccache)
    find_program(_ccache_path NAMES "ccache")
    if(NOT _ccache_path)
        message(FATAL_ERROR "'ccache' executable not found!")
        return()
    endif()

    _enable_ccache()
endfunction()

function(enable_ccache_if_possible)
    find_program(_ccache_path NAMES "ccache")
    if(NOT _ccache_path)
        message(STATUS "ccache support not enabled: the executable was not found")
        return()
    endif()

    if(NOT CMAKE_GENERATOR MATCHES "Ninja|Makefiles|Xcode")
        message(STATUS "ccache support not enabled: unsupported generator '${CMAKE_GENERATOR}'")
        return()
    endif()

    _enable_ccache()
endfunction()
