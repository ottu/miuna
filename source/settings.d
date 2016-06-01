module settings;

import std.stdio;
import std.array;
import std.algorithm;
import std.file;
import std.json;
import std.typecons;

enum TargetArch: string
{
    Arch = "arch",
    Ubuntu = "ubuntu"
}

struct BootStrap
{
    TargetArch arch;
    string command;
    string[] options;
    Nullable!string cache_path = null;
    Nullable!string mirror = null;
}

struct Settings
{
    string current_path;
    string machinectl = "machinectl";
    BootStrap[] bootstraps;
    string container_root;
    string playbooks_path;
    string ansible_python_interpreter;
}

Settings load_settings_( string current_path )
{
    auto settings = Settings();

    auto json = parseJSON(readText("settings.json"));

    settings.current_path = current_path;
    settings.container_root = json["container_root"].str;
    settings.playbooks_path = json["playbooks_path"].str;
    settings.ansible_python_interpreter = json["ansible_python_interpreter"].str;

    foreach(key, value; json["bootstraps"].object)
    {
        auto bootstrap = BootStrap();
        switch (key)
        {
            case TargetArch.Arch:
            {
                bootstrap.arch = TargetArch.Arch;
                bootstrap.cache_path = value["cache_path"].str;
            } break;

            case TargetArch.Ubuntu:
            {
                bootstrap.arch = TargetArch.Ubuntu;
                bootstrap.mirror = value["mirror"].str;
            } break;

            default: {}
        }

        bootstrap.command = value["command"].str;
        bootstrap.options = value["options"].array.map!("a.str").array;

        settings.bootstraps ~= bootstrap;
    }

    writeln(settings);
    return settings;
}
