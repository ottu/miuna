import std.stdio;
import std.string;
import std.array;
import std.range;
import std.conv;
import std.algorithm;
import std.process;
import std.file;
import std.path;
import std.json;

import settings;

enum SubCommand : string
{
    Init = "init",
    Create = "create",
    Delete = "delete",
    Start = "start",
    Restart = "restart",
    Poweroff = "poweroff",
//    Terminate = "terminate",
    List = "list",
    Playbook = "playbook"
}

void command_start(string name)
{
    writeln("start %s".format(name));
    //execute( [machinectl, "start", name] );
    execute( ["systemctl", "start", "systemd-nspawn@" ~ name] );
    return;
}

void command_poweroff(string name)
{
    writeln("poweroff %s".format(name));
    //execute( [machinectl, "poweroff", name] );
    execute( ["systemctl", "stop", "systemd-nspawn@" ~ name] );
    return;
}

private uint exec_ansible(string[] command_line)
{
    auto pid = spawnProcess( command_line, std.stdio.stdin, std.stdio.stdout );

    if (wait(pid) != 0)
    {
        return 1;
    }
    return 0;
}

uint command_playbook(string name, Settings settings, bool isInit=false)
{
    chdir(settings.playbooks_path);

    string container_path = settings.container_root ~ "/" ~ name;

    string[] command_line = [
        "ansible-playbook", "%s.yml".format(isInit ? "init": name),
        "-e", "target=%s".format(name),
        "-e", "container_root=%s".format(settings.container_root),
        "-i", "%s,".format(container_path),
        "--diff"
    ];

    writeln(command_line);

    chdir(settings.current_path);
    return exec_ansible(command_line);
}

uint command_playbook_all(Settings settings)
{
    chdir(settings.playbooks_path);

    auto list = execute( [settings.machinectl, "list"] );
    string inventories;
    foreach(line; list.output.splitLines[1..$-2])
    {
        string name = line.split[0];
        string container_path = settings.container_root ~ "/" ~ name ~ ",";
        inventories ~= container_path;
    }

    string[] command_line = [
        "ansible-playbook", "all.yml",
        "-i", "%s,".format(inventories)
    ];

    writeln(command_line);

    chdir(settings.current_path);
    return exec_ansible(command_line);
}

int main( string[] args )
{
    Settings settings = load_settings(dirName(args[0]));

    SubCommand sub = cast(SubCommand)(args[1]);

    final switch (sub)
    {
        case SubCommand.Init:
        {
            if (!exists(settings.nspawn_dir)) {
                writefln("create %s", settings.nspawn_dir);
                mkdir(settings.nspawn_dir);
            }

            writeln("enable systemd machines.target");
            execute( ["systemctl", "enable", "machines.target"] );

            writeln("******************************************");
            writeln("*************** CAUTION ******************");
            writeln("******************************************");
            writeln("** please configure enable bridge \"br0\" **");
            writeln("******************************************");
        } break;

        case SubCommand.Create:
        {
            string container_name = args[2];
            string container_path = settings.container_root ~ container_name;

            if (exists(container_path))
            {
                writefln( "%s was already exists!", container_path );
                return 1;
            }

            mkdir( container_path );

            TargetArch arch = cast(TargetArch)(args[3]);
            auto bootstrap = settings.bootstraps[arch];

            writeln(bootstrap);

            string[] commandline;
            final switch (arch)
            {
                case TargetArch.Arch: { commandline = bootstrap.compileArch(container_path); } break;
                case TargetArch.Ubuntu: { commandline = bootstrap.compileUbuntu(container_path, args[4]); } break;
            }

            writeln(commandline);
            auto pid = spawnProcess( commandline, std.stdio.stdin, std.stdio.stdout );

            if (wait(pid) != 0)
            {
                writeln("bootstrap failed!");
                rmdirRecurse( container_path );
                return 1;
            } else {
                writeln("bootstrap success!!");
            }

            assert( exists( container_path ), "%s not found.".format(container_path) );

            writeln("==========================");
            writeln("===== initial setups =====");
            writeln("==========================");

            final switch(arch)
            {
                case TargetArch.Arch:
                {
                    writeln("add pts/0 to securetty...");
                    append( container_path~"/etc/securetty", "pts/0");
                } break;

                case TargetArch.Ubuntu:
                {
                    auto pipe = pipeProcess(["systemd-nspawn", "-D", container_path], Redirect.stdin);

                    writeln("change root passwd to \"root\", please rechange manually.");
                    pipe.stdin.writeln("passwd");
                    pipe.stdin.writeln("root");   // type
                    pipe.stdin.writeln("root");   // retype

                    writeln("enable dbus");
                    pipe.stdin.writeln("/lib/systemd/systemd-sysv-install enable dbus");

                    pipe.stdin.flush();
                    pipe.stdin.close();

                    if (wait(pipe.pid) != 0) {
                        writeln("pipeProcess exec failed!");
                    }
                } break;
            }

            writeln("make container setting file for " ~ container_name);
            auto f = File(settings.nspawn_dir ~ "/" ~ container_name ~ ".nspawn", "w");
            f.writeln("[Files]");
            f.writeln("Bind=/var/cache/pacman/pkg:/var/cache/pacman/pkg");
            f.writeln("[Network]");
            f.writeln("Bridge=br0");

            writeln("override /etc/systemd/network/80-container-host0.network");
            execute( ["ln", "-sf", "/dev/null", container_path ~ "/etc/systemd/network/80-container-host0.network"] );

            writeln("check exists %s/init.yml".format(settings.playbooks_path));
            if( exists(settings.playbooks_path ~ "/init.yml") ) {
                writeln("%s/init.yml found. exec playbook.");
                command_playbook(container_name, settings, true);
            }

            writeln("enable autoboot %s".format(container_name));
            //execute( [machinectl, "enable", container_name] );
            execute( ["systemctl", "enable", "systemd-nspawn@" ~ container_name] );

            command_start(container_name);
        } break;

        case SubCommand.Delete:
        {
            string container_name = args[2];
            string container_path = settings.container_root ~ container_name;

            command_poweroff(container_name);

            writeln("disable autoboot %s".format(container_name));
            //execute( [machinectl, "disable", container_name] );
            execute( ["systemctl", "disable", "systemd-nspawn@" ~ container_name] );

            writeln("remove VM: %s".format(container_path));
            rmdirRecurse( container_path );
            remove(settings.nspawn_dir ~ "/" ~ container_name ~ ".nspawn");
        } break;

        case SubCommand.Start:
        {
            string container_name = args[2];
            command_start(container_name);
        } break;

        case SubCommand.Restart:
        {
            string container_name = args[2];
            command_poweroff(container_name);
            command_start(container_name);
        } break;

        case SubCommand.Poweroff:
        {
            string container_name = args[2];
            command_poweroff(container_name);
        } break;

//        case SubCommand.Terminate:
//        {
//            string container_name = args[2];
//            writeln("terminate %s".format(container_name));
//            execute( [machinectl, "terminate", container_name] );
//        } break;

        case SubCommand.List:
        {
            struct VM
            {
                enum Status { RUNNING, STOPPED }
                string name;
                Status status;
                string address = "none";
            }

            auto list = execute( [settings.machinectl, "list"] );
            auto images = execute( [settings.machinectl, "list-images"] );

            VM[] vms;

            foreach(line; list.output.splitLines[1..$-2])
            {
                string name = line.split[0];
                auto p = pipe();
                auto sid = spawnProcess(["machinectl", "status", name], stdin, p.writeEnd);
                wait(sid);
                auto output = pipe();
                auto gid = spawnProcess(["grep", "Address"], p.readEnd, output.writeEnd);
                wait(gid);

                string address = output.readEnd.byLine.map!(l => l.split(":")[1].strip.to!string).array[0];
                vms ~= VM(name, VM.Status.RUNNING, address);
            }

            foreach(line; images.output.splitLines[1..$-2])
            {
                string name = line.split[0];
                if( vms.filter!(a => a.name == name).empty )
                    vms ~= VM(name, VM.Status.STOPPED);
            }

            writeln("[NAME]          [STATUS] [ADDRESS]");
            foreach(vm; vms)
                writeln(vm.name ~
                        to!string(' '.repeat.take(15-vm.name.length).array) ~
                        " " ~
                        to!string(vm.status) ~
                        "  " ~
                        vm.address
                        );

        } break;

        case SubCommand.Playbook:
        {
            string container_name = args[2];

            if (container_name == "all") {
                command_playbook_all(settings);
            } else {
                command_playbook(container_name, settings);
            }
        } break;
    }

    return 0;
}
