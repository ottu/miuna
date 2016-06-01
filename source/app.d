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

uint command_playbook(string name, Settings settings, bool isInit=false)
{
    chdir(settings.playbooks_path);

    string container_path = settings.container_root ~ "/" ~ name;

    string[] command_line = [
        "ansible-playbook", "%s.yml".format(isInit ? "init": name),
        "-e", "target=%s".format(name),
        "-e", "container_root=%s".format(settings.container_root),
        "-i", "%s,".format(container_path),
        "-e", "ansible_python_interpreter=%s".format(settings.ansible_python_interpreter)
    ];

    writeln(command_line);

    auto pid = spawnProcess( command_line, std.stdio.stdin, std.stdio.stdout );

    chdir(settings.current_path);

    if (wait(pid) != 0)
    {
        return 1;
    }
    return 0;
}

int main( string[] args )
{
    Settings settings = load_settings(dirName(args[0]));

    SubCommand sub = cast(SubCommand)(args[1]);

    final switch (sub)
    {
        case SubCommand.Init:
        {
            writeln("change /usr/lib/systemd/system/systemd-nspawn@.service");
            execute( ["sed", "-i", "-e", "s/^ExecStart.*$/ExecStart=\\/usr\\/bin\\/systemd-nspawn --quiet --keep-unit --boot --link-journal=try-guest --network-bridge=br0 --settings=override --machine=%I --bind=\\/var\\/cache\\/pacman\\/pkg", "/usr/lib/systemd/system/systemd-nspawn@.service"] );

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
                    writeln("remove securetty...");
                    remove( container_path ~ "/etc/securetty" );

                    writeln("override /etc/systemd/network/80-container-host0.network");
                    execute( ["ln", "-sf", "/dev/null", container_path ~ "/etc/systemd/network/80-container-host0.network"] );
                } break;

                case TargetArch.Ubuntu:
                {
                } break;
            }

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
            }

            auto list = execute( [settings.machinectl, "list"] );
            auto images = execute( [settings.machinectl, "list-images"] );

            VM[] vms;

            foreach(line; list.output.splitLines[1..$-2])
                vms ~= VM(line.split[0], VM.Status.RUNNING);

            foreach(line; images.output.splitLines[1..$-2])
            {
                string name = line.split[0];
                if( vms.filter!(a => a.name == name).empty )
                    vms ~= VM(name, VM.Status.STOPPED);
            }

            writeln("[NAME]          [STATUS]");
            foreach(vm; vms)
                writeln(vm.name ~ to!string(' '.repeat.take(15-vm.name.length).array) ~ " " ~ to!string(vm.status));

        } break;

        case SubCommand.Playbook:
        {
            string container_name = args[2];
            command_playbook(container_name, settings);
        } break;
    }

    return 0;
}
