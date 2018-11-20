module settings;

import std.stdio;
import std.string;
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
    string[] extras;
    Nullable!string cache_path = null;
    Nullable!string mirror = null;

    this(TargetArch arch) { this.arch = arch; }

    string[] compileArch(string container_path)
    {
        assert(arch == TargetArch.Arch);
        return [command] ~ options ~ [container_path, "base"] ~ extras;
    }

    string[] compileUbuntu(string container_path, string dist)
    {
        assert(arch == TargetArch.Ubuntu);
        return [command] ~ options ~ ["--include=dbus,%s".format(extras.join(","))] ~ [dist, container_path, mirror];
    }
}

struct Settings
{
    string current_path;
    string machinectl = "machinectl";
    BootStrap[TargetArch] bootstraps;
    string container_root;
    string playbooks_path;
}

Settings load_settings( string current_path )
{
    auto settings = Settings();

    auto json = parseJSON(readText("settings.json"));

    assert(current_path != "", "invalid current_path");
    assert(json["container_root"].str != "", "undefined container_root key on settings.json");
    assert(json["playbooks_path"].str != "", "undefined playbooks_path key on settings.json");

    settings.current_path = current_path;
    settings.container_root = json["container_root"].str;
    settings.playbooks_path = current_path ~ "/" ~ json["playbooks_path"].str;

    foreach(key, value; json["bootstraps"].object)
    {
        assert(value["command"].str != "", "undefined %s's command key on settings.json".format(key));

        auto arch = cast(TargetArch)(key);
        auto bootstrap = BootStrap(arch);
        final switch (arch)
        {
            case TargetArch.Arch:
            {
                bootstrap.cache_path = value["cache_path"].str;
            } break;

            case TargetArch.Ubuntu:
            {
                bootstrap.mirror = value["mirror"].str;
            } break;
        }

        bootstrap.command = value["command"].str;
        bootstrap.options = value["options"].array.map!("a.str").array;
        bootstrap.extras = value["extras"].array.map!("a.str").array;

        settings.bootstraps[key] = bootstrap;
    }

    return settings;
}
