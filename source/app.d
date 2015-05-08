import std.stdio;
import std.string;
import std.process;
import std.file;

enum SubCommand : string
{
    Create = "create",
    Delete = "delete",
    Start = "start",
    Stop = "stop"
}

int main( string[] args )
{
    string pacstrap = "pacstrap";
    string nspawn = "systemd-nspawn";
    string container_root = "/var/lib/container/";

    writeln( args );
    SubCommand sub = cast(SubCommand)(args[1]);
    writeln(sub);

    final switch (sub)
    {
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
                    [pacstrap, "-i", "-c", "-d", container_path],
                    std.stdio.stdin,
                    std.stdio.stdout
                );

            if (wait(pid) != 0)
            {
                writeln("pacstrap failed!");
                rmdirRecurse( container_path );
                return 1;
            }

            assert( exists( container_path ), "%s not found.".format(container_path) );
            remove( container_path ~ "/etc/securetty" );

            auto temp = execute( ["machinectl", "enable", container_name] );
            temp = execute( ["machinectl", "start", container_name] );
        } break;

        case SubCommand.Delete:
        {

        } break;

        case SubCommand.Start:
        {
            string container_name = args[2];

        } break;

        case SubCommand.Stop:
        {

        } break;
    }

    return 0;
}
