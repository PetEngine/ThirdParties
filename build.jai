Build :: enum_flags u64 {
    shaderc;
}

#run {
    set_build_options_dc(.{ do_output = false });

    build := parseCommandLine();
    if !build return;

    wd := get_working_directory();
    if !wd {
        fatal("get_working_directory() has failed");
    }
    defer set_working_directory(wd);

    if !set_working_directory(#filepath) {
        fatal("set_working_directory(\"%\") has failed", #filepath);
    }

    if !make_directory_if_it_does_not_exist("output") {
        fatal("make_directory_if_it_does_not_exist(\"output\") has failed");
    }

    if build & .shaderc {
        if !buildShaderc()            then fatal("shaderc build has failed");
        if !generateShadercBindings() then fatal("shaderc bindings generation has failed");
    }
}

buildShaderc :: () -> bool #compile_time {
    write_string("\n>>> shaderc build has started\n");

    if !file_exists("shaderc/build") {
        result := run_command("python", "shaderc/utils/git-sync-deps");
        if result.type != .EXITED || result.exit_code != 0 {
            error("\"python ./utils/git-sync-deps\" has failed: %", result);
            return false;
        }

        if !make_directory_if_it_does_not_exist("shaderc/build") {
            error("make_directory_if_it_does_not_exist(\"shaderc/build\") has failed\n");
            return false;
        }

        result = run_command("cmake", "-S", "shaderc", "-B", "shaderc/build");
        if result.type != .EXITED || result.exit_code != 0 {
            error("\"cmake generation\" has failed: %", result);
            return false;
        }
    }

    result := run_command("cmake", "--build", "shaderc/build", "--config", "RelWithDebInfo", "--parallel");
    if result.type != .EXITED || result.exit_code != 0 {
        error("cmake build has failed: %", result);
        return false;
    }

    write_string(">>> shaderc build has ended\n");
    return true;
}

generateShadercBindings :: () -> bool #compile_time {
    write_string("\n>>> shaderc bindings generation has started\n");

    delete_directory("output/shaderc");
    if !make_directory_if_it_does_not_exist("output/shaderc/bin", true) {
        error("make_directory_if_it_does_not_exist(\"output/shaderc/bin\") has failed\n");
        return false;
    }

    if !copy_file("shaderc/build/libshaderc/RelWithDebInfo/shaderc_shared.dll", "output/shaderc/bin/shaderc_shared.dll") {
        error("copy_file(shaderc_shared.dll) has failed");
        return false;
    }
    if !copy_file("shaderc/build/libshaderc/RelWithDebInfo/shaderc_shared.lib", "output/shaderc/bin/shaderc_shared.lib") {
        error("copy_file(shaderc_shared.lib) has failed");
        return false;
    }
    if !copy_file("shaderc/LICENSE", "output/shaderc/LICENSE") {
        error("copy_file(LICENSE) has failed");
        return false;
    }

    options : Generate_Bindings_Options;
    options.alias_original_enum_names = false;

    array_add(*options.library_search_paths, "shaderc/build/libshaderc/RelWithDebInfo");
    array_add(*options.libraries,            .{ "shaderc_shared", "shaderc" });

    array_add(*options.include_paths, "shaderc/libshaderc/include");
    array_add(*options.source_files,  "shaderc/shaderc.h");

    // array_add(*options.strip_prefixes, "shaderc");

    result_builder, success := generate_bindings(options, true);
    if !success {
        error("generate_bindings has failed\n");
        return false;
    }

    result := builder_to_string(*result_builder,, allocator = temp);
    result  = replace(result, "shaderc/build/libshaderc/RelWithDebInfo", "bin",, allocator = temp);

    if !write_entire_file("output/shaderc/module.jai", result) {
        error("write_entire_file has failed");
        return false;
    }

    write_string(">>> shaderc bindings generation has ended\n");
    return true;
}

parseCommandLine :: () -> Build #compile_time {
    INFO :: type_info(Build);
    #assert INFO.type == .ENUM;

    build_options := get_build_options();

    if !build_options.compile_time_command_line {
        write_string("Specify the name of third-party to build");
        return 0;
    }

    build : Build;

    for command_line_argument : build_options.compile_time_command_line {
        if command_line_argument == "all" {
            for INFO.values { build |= cast(Build) it; }
            break;
        }

        for INFO.names {
            if it == command_line_argument {
                build |= cast(Build) INFO.values[it_index];
                continue command_line_argument;
            }
        }

        fatal("Unrecognized command line argument: \"%\"", command_line_argument);
    }

    return build;
}

error :: (format : string, args : ..Any, location := #caller_location) #compile_time {
    message := tprint(format, ..args);
    compiler_report(message, location, .ERROR_CONTINUABLE);
}

fatal :: (format : string, args : ..Any, location := #caller_location) #compile_time {
    message := tprint(format, ..args);
    compiler_report(message, location, .ERROR);
}

#import "Basic";
#import "Bindings_Generator";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Process";
#import "String";
