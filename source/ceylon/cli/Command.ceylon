void asd() {
    value app = Application {
        name = "helloworld";
        arguments = {
            Flag {
                name = "moshimoshi";
                validator = (Integer count) => count > 0;
            },
            Optional {
                name = "hej";
                validator = ({String*} values) => values.size;
            }
        };
        subcommands = {
            Subcommand {
                name = "goodbye";
                arguments = {
                    Positional {
                        name = "farewell";
                        validator = ({String+} values) => "".join(values);
                    }
                };
                subcommands = {
                    Subcommand {
                        name = "meh";
                        arguments = {
                            Flag {
                                name = "mleh";
                                validator = (Integer count) => count;
                            }
                        };
                    }
                };
            }
        };
    };
    value results = app.parseWithExit();
    
    if (is Boolean moshimoshi = results["moshimoshi"]) {
        print(moshimoshi);
    }
    if (is Integer hej = results["hej"]) {
        print(hej);
    }
    if (is Map<String,Anything> goodbye = results["goodbye"]) {
        if (is String farewell = goodbye["hej"]) {
            print(farewell);
        }
    }
}

shared abstract class Command<Results, SubResults>(
    name,
    about = minimalAbout<Results,SubResults>,
    usage = standardUsage<Results,SubResults>,
    arguments = empty,
    subcommands = empty,
    groups = empty,
    helpShort = 'h',
    aboutShort = 'V',
    help = standardHelp<Results,SubResults>)
//        of Application | Subcommand {
{
    "Parsable name of the command. Should be lowercase, but must not contain
     whitespace."
    shared String name;
    "Human readable description of the command"
    see (`function verboseAbout`, `function moduleAbout`)
    shared String|String(Command<Results,SubResults>) about;
    "Usage text"
    shared String|String(Command<Results,SubResults>) usage;
    "Arguments for the current command"
    shared {Argument<Results>*} arguments;
    "Nested commands"
    shared {Subcommand<SubResults,Nothing>*} subcommands;
    "Argument groups"
    shared {ArgumentGroup*} groups;
    "The short form of the help flag"
    shared Character helpShort;
    "The short form of the about flag"
    shared Character aboutShort;
    "Help text"
    shared String|String(Command<Results,SubResults>) help;
    
    shared Map<String,Results|Map<String,SubResults>>|ParseError parse(
        rawArguments = process.arguments) {
        {String*} rawArguments;
        return nothing;
    }
}

shared class Application<Results, SubResults>(
    name,
    about = minimalAbout<Results,SubResults>,
    usage = standardUsage<Results,SubResults>,
    arguments = empty,
    subcommands = empty,
    groups = empty,
    helpShort = 'h',
    aboutShort = 'V',
    help = standardHelp<Results,SubResults>)
        extends Command<Results,SubResults>(
    name,
    about,
    usage,
    arguments,
    subcommands,
    groups,
    helpShort,
    aboutShort,
    help
) {
    "Parsable name of the command. Should be lowercase, but must not contain
     whitespace."
    String name;
    "Human readable description of the command"
    see (`function verboseAbout`, `function moduleAbout`)
    String|String(Command<Results,SubResults>) about;
    "Usage text"
    String|String(Command<Results,SubResults>) usage;
    "Arguments for the current command"
    {Argument<Results>*} arguments;
    "Nested commands"
    {Subcommand<SubResults,Nothing>*} subcommands;
    "Argument groups"
    {ArgumentGroup*} groups;
    "The short form of the help flag"
    Character helpShort;
    "The short form of the about flag"
    Character aboutShort;
    "Help text"
    String|String(Command<Results,SubResults>) help;
    
    "Exits after printing an error message where a [[ParseError]] would be
     returned by [[Command.parse]]."
    shared Map<String,Results|Map<String,SubResults>> parseWithExit(
        rawArguments = process.arguments,
        exit_code = 1) {
        {String*} rawArguments;
        Integer exit_code;
        return nothing;
    }
}

shared class Subcommand<Results, SubResults>(
    name,
    about = "",
    usage = standardUsage<Results,SubResults>,
    arguments = empty,
    subcommands = empty,
    groups = empty,
    helpShort = 'h',
    aboutShort = 'V',
    help = standardHelp<Results,SubResults>)
        extends Command<Results,SubResults>(
    name,
    about,
    usage,
    arguments,
    subcommands,
    groups,
    helpShort,
    aboutShort,
    help
) {
    "Parsable name of the command. Should be lowercase, but must not contain
     whitespace."
    String name;
    "Human readable description of the command"
    String|String(Command<Results,SubResults>) about;
    "Usage text"
    String|String(Command<Results,SubResults>) usage;
    "Arguments for the current command"
    {Argument<Results>*} arguments;
    "Nested commands"
    {Subcommand<SubResults,Nothing>*} subcommands;
    "Argument groups"
    {ArgumentGroup*} groups;
    "The short form of the help flag"
    Character helpShort;
    "The short form of the about flag"
    Character aboutShort;
    "Help text"
    String|String(Command<Results,SubResults>) help;
    
    "Return a view of this subcommand with the given command as the parent.
     Typically called by the parent command itself."
    shared Subcommand<Results,SubResults> withParent(Command<Results,SubResults> parent) {
        return nothing;
    }
}
