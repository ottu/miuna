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

string machinectl = "machinectl";
string bootstrap;
string container_root;
string pacman_cache_path;

void load_settings()
{
    auto json = parseJSON(readText("settings.json"));

    bootstrap = json["bootstrap_command"].str;
    container_root = json["container_root"].str;
    pacman_cache_path = json["pacman_cache_path"].str;

    assert(bootstrap != "",         "undefined bootstrap_command key on setting.json.");
    assert(container_root != "",    "undefined container_root key on setting.json.");
    assert(pacman_cache_path != "", "undefined pacman_cache_path key on setting.json.");
}

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

int main( string[] args )
{
    load_settings();

    writeln( args );
    SubCommand sub = cast(SubCommand)(args[1]);
    writeln(sub);

    final switch (sub)
    {
        case SubCommand.Init:
        {
            writeln("change /usr/lib/systemd/system/systemd-nspawn@.service");
            execute( ["sed", "-i", "-e", "s/^ExecStart.*$/ExecStart=\\/usr\\/bin\\/systemd-nspawn --quiet --keep-unit --boot --link-journal=try-guest --network-bridge=br0 --settings=override --machine=%I --bind=\\/var\\/cache\\/pacman\\/pkg:\\/var\\/cache\\/pacman\\/pkg-host/", "/usr/lib/systemd/system/systemd-nspawn@.service"] );

            writeln("******************************************");
            writeln("*************** CAUTION ******************");
            writeln("******************************************");
            writeln("** please configure enable bridge \"br0\" **");
            writeln("******************************************");
        } break;

        case SubCommand.Create:
        {
            string container_name = args[2];
            string container_path = container_root ~ container_name;

            if (exists(container_path))
            {
                writefln( "%s was already exists!", container_path );
                return 1;
            }

            mkdir( container_path );

            auto pid =
                spawnProcess(
                    [bootstrap, "-i", "-c", "-d", container_path],
                    std.stdio.stdin,
                    std.stdio.stdout
                );

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

            writeln("remove securetty...");
            remove( container_path ~ "/etc/securetty" );

            writeln("modify pacman cache dir...");
            execute( ["sed", "-i", "-e", "s/^#CacheDir.*$/CacheDir = \\/var\\/cache\\/pacman\\/pkg-host\\//", container_path ~ "/etc/pacman.conf"] );

            writeln("override /etc/systemd/network/80-container-host0.network");
            execute( ["ln", "-sf", "/dev/null", container_path ~ "/etc/systemd/network/80-container-host0.network"] );

            writeln("enable autoboot %s".format(container_name));
            //execute( [machinectl, "enable", container_name] );
            execute( ["systemctl", "enable", "systemd-nspawn@" ~ container_name] );

            command_start(container_name);
        } break;

        case SubCommand.Delete:
        {
            string container_name = args[2];
            string container_path = container_root ~ container_name;

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

            auto list = execute( [machinectl, "list"] );
            auto images = execute( [machinectl, "list-images"] );

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
            writeln(args[0]);
            chdir(dirName(args[0]) ~ "/playbooks");

            string container_name = args[2];
            auto pid =
                spawnProcess(
                    ["ansible-playbook", "%s.yml".format(container_name), "-e", "target=%s".format(container_name), "-e", "container_root=%s".format(container_root)],
                    std.stdio.stdin,
                    std.stdio.stdout
                );

            if (wait(pid) != 0)
            {
                return 1;
            }

        } break;
    }

    return 0;
}
