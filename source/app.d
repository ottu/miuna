import std.stdio;
import std.string;
import std.process;
import std.file;

string machinectl = "machinectl";
string pacstrap = "pacstrap";
string nspawn = "systemd-nspawn";
string container_root = "/var/lib/container/";
string pacman_cache_path = "/var/cache/pacman/pkg";

enum SubCommand : string
{
    Create = "create",
    Delete = "delete",
    Start = "start",
    Restart = "restart",
    Poweroff = "poweroff",
    Terminate = "terminate",
    List = "list"
}

void command_start(string name)
{
    writeln("start %s".format(name));
    execute( [machinectl, "start", name] );

    writeln("bind pacman cache dir to /var/cache/pacman/pkg-host");
    execute( [machinectl, "--bind", pacman_cache_path, pacman_cache_path~"-host", "--mkdir"] );
    return;
}

void command_poweroff(string name)
{
    writeln("poweroff %s".format(name));
    execute( [machinectl, "poweroff", name] );
    return;
}

int main( string[] args )
{
    writeln( args );
    SubCommand sub = cast(SubCommand)(args[1]);
    writeln(sub);

    string container_name = "";
    if(sub != SubCommand.List) container_name = args[2];

    final switch (sub)
    {
        case SubCommand.Create:
        {
            string container_path = container_root ~ container_name;

            if (exists(container_path))
            {
                writefln( "%s was already exists!", container_path );
                return 1;
            }

            mkdir( container_path );

            auto pid =
                spawnProcess(
                    [pacstrap, "-i", "-c", "-d", container_path],
                    std.stdio.stdin,
                    std.stdio.stdout
                );

            if (wait(pid) != 0)
            {
                writeln("pacstrap failed!");
                rmdirRecurse( container_path );
                return 1;
            } else {
                writeln("pacstrap success!!");
            }

            assert( exists( container_path ), "%s not found.".format(container_path) );

            writeln("==========================");
            writeln("===== initial setups =====");
            writeln("==========================");

            writeln("remove securetty...");
            remove( container_path ~ "/etc/securetty" );

            writeln("modify pacman cache dir...");
            execute( ["sed", "-i", "-e", "s/^#CacheDir.*$/CacheDir = \\/var\\/cache\\/pacman\\/pkg-host\\//", container_path ~ "/etc/pacman.conf"] );

            writeln("enable autoboot %s".format(container_name));
            execute( [machinectl, "enable", container_name] );

            command_start(container_name);
        } break;

        case SubCommand.Delete:
        {
            string container_path = container_root ~ container_name;

            command_poweroff(container_name);

            writeln("disable autoboot %s".format(container_name));
            execute( [machinectl, "disable", container_name] );

            writeln("remove VM: %s".format(container_path));
            rmdirRecurse( container_path );
        } break;

        case SubCommand.Start:
        {
            command_start(container_name);
        } break;

        case SubCommand.Restart:
        {
            command_poweroff(container_name);
            command_start(container_name);
        } break;

        case SubCommand.Poweroff:
        {
            command_poweroff(container_name);
        } break;

        case SubCommand.Terminate:
        {
            writeln("terminate %s".format(container_name));
            execute( [machinectl, "terminate", container_name] );
        } break;

        case SubCommand.List:
        {
            auto pid =
                spawnProcess(
                    [machinectl, "list"],
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
