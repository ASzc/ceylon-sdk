shared abstract class Command<Results>(
    name,
    about = minimalAbout,
    usage = standardUsage,
    arguments = empty,
    subcommands = empty,
    groups = empty,
    helpShort = 'h',
    aboutShort = 'V',
    help = standardHelp)
//        of Application | Subcommand {
{
    "Parsable name of the command. Should be lowercase, but must not contain
     whitespace."
    shared String name;
    "Human readable description of the command"
    see (`function verboseAbout`, `function moduleAbout`)
    shared String|String(Command<Results>) about;
    "Usage text"
    shared String|String(Command<Results>) usage;
    "Arguments for the current command"
    shared {Argument<Results>*} arguments;
    "Nested commands"
    shared {Subcommand<Results>*} subcommands;
    "Argument groups"
    shared {ArgumentGroup*} groups;
    "The short form of the help flag"
    shared Character helpShort;
    "The short form of the about flag"
    shared Character aboutShort;
    "Help text"
    shared String|String(Command<Results>) help;
    
    shared Map<String,String|{String+}|Boolean>|ParseError parseWithoutExit(
        rawArguments = process.arguments) {
        {String*} rawArguments;
        
        Map<Integer,Integer|String|Boolean> asd = map { 1->2, 2->"", 3->true };
        
        return nothing;
    }
}

shared class Application<Results>(
    name,
    about = minimalAbout,
    usage = standardUsage,
    arguments = empty,
    subcommands = empty,
    groups = empty,
    helpShort = 'h',
    aboutShort = 'V',
    help = standardHelp)
        extends Command<Results>(
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
    String|String(Command<Results>) about;
    "Usage text"
    String|String(Command<Results>) usage;
    "Arguments for the current command"
    {Argument<Results>*} arguments;
    "Nested commands"
    {Subcommand<Results>*} subcommands;
    "Argument groups"
    {ArgumentGroup*} groups;
    "The short form of the help flag"
    Character helpShort;
    "The short form of the about flag"
    Character aboutShort;
    "Help text"
    String|String(Command<Results>) help;
    
    shared Map<String,String|{String+}|Boolean>|ParseError parse(
        rawArguments = process.arguments,
        exit_code = 1) {
        {String*} rawArguments;
        Integer exit_code;
        
        return nothing;
    }
}

shared class Subcommand<Results>(
    name,
    about = "",
    usage = standardUsage,
    arguments = empty,
    subcommands = empty,
    groups = empty,
    helpShort = 'h',
    aboutShort = 'V',
    help = standardHelp)
        extends Command<Results>(
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
    String|String(Command<Results>) about;
    "Usage text"
    String|String(Command<Results>) usage;
    "Arguments for the current command"
    {Argument<Results>*} arguments;
    "Nested commands"
    {Subcommand<Results>*} subcommands;
    "Argument groups"
    {ArgumentGroup*} groups;
    "The short form of the help flag"
    Character helpShort;
    "The short form of the about flag"
    Character aboutShort;
    "Help text"
    String|String(Command<Results>) help;
    
    "Return a view of this subcommand with the given command as the parent.
     Typically called by the parent command itself."
    shared Subcommand<Results> withParent(Command<Results> parent) {
        return nothing;
    }
}
