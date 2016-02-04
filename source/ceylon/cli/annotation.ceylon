import ceylon.language.meta.declaration {
    ValueDeclaration,
    FunctionDeclaration,
    ClassDeclaration
}
import ceylon.language.meta.model {
    Function,
    Class,
    Value
}

Integer countValues({String*} values) {
    return values.size;
}

abstract class Bleh(helloCount) {
    coerce (`function countValues`)
    shared Integer helloCount;
}

shared final annotation class CoerceAnnotation(shared FunctionDeclaration coercer)
        satisfies OptionalAnnotation<CoerceAnnotation,ValueDeclaration> {
}

shared annotation CoerceAnnotation coerce(FunctionDeclaration coercer)
        => CoerceAnnotation(coercer);

///
///
///
///
///
///
///
///
///
///
///

shared final annotation class ShortAnnotation(shared Character key)
        satisfies OptionalAnnotation<ShortAnnotation,ValueDeclaration> {
}
shared annotation ShortAnnotation short(Character key)
        => ShortAnnotation(key);

shared final annotation class LongAnnotation(shared String key)
        satisfies OptionalAnnotation<LongAnnotation,ValueDeclaration> {
}
shared annotation LongAnnotation long(String key)
        => LongAnnotation(key);

// TODO ...

shared final annotation class HiddenAnnotation()
        satisfies OptionalAnnotation<HiddenAnnotation,ValueDeclaration> {
}
shared annotation HiddenAnnotation hidden()
        => HiddenAnnotation();

//shared annotation FlagAnnotation flag(
//    String name,
//    Character? short=null, 
//    String? long=null, 
//    String help="", 
//    {String*} conflictsWith=empty,
//    {String*} overridesWith=empty,
//    {String*} requires=empty,
//    Boolean inheritable=false
//    Boolean hidden = false)
//        => FlagAnnotation(name);

shared final annotation class FlagAnnotation(shared String name)
        satisfies OptionalAnnotation<FlagAnnotation,ValueDeclaration> {
}
shared annotation FlagAnnotation flag(String name)
        => FlagAnnotation(name);

shared final annotation class OptionAnnotation(shared String name)
        satisfies OptionalAnnotation<OptionAnnotation,ValueDeclaration> {
}
shared annotation OptionAnnotation option(String name)
        => OptionAnnotation(name);

shared final annotation class ParameterAnnotation(shared String name)
        satisfies OptionalAnnotation<ParameterAnnotation,ValueDeclaration> {
}
shared annotation ParameterAnnotation parameter(String name)
        => ParameterAnnotation(name);

shared final annotation class CommandAnnotation(shared String name)
        satisfies OptionalAnnotation<CommandAnnotation,ClassDeclaration> {
}
shared annotation CommandAnnotation command(String name)
        => CommandAnnotation(name);

command("greetings")
class CommandAbc(flagCount, flagPresent, optionCount, optionOptional) {
    flag ("hello")
    short('o')
    long("helloworld")
    Integer flagCount;
    
    flag ("hej")
    short('j')
    Boolean flagPresent;
    
    option ("hi")
    long("hiworld")
    hidden
    Integer optionCount;
    
    option ("blah")
    String? optionOptional;
    
    command("goodbye")
    class SubcommandQwe(bleh) {
        option ("bleh")
        String? bleh;
    }
}

Map<String,Object(Integer)> defaultFlagCoercers = map{
    "count" -> ((Integer i) => i),
    "exists" -> ((Integer i) => i > 0)
};

Map<String,Anything({String*})> defaultOptionCoercers = map{
     "count"->(({String*} s) => s.size),
     "single"->(({String*} s) => s.first)
 };

shared ParseError? parse(
    rootCommand,
    rawArguments = process.arguments,
    flagCoercers = defaultFlagCoercers,
    optionCoercers = defaultOptionCoercers,
    parameterCoercers = nothing) {
    Class<Object,Anything> rootCommand;
    {String*} rawArguments;
    Map<String,Anything(Integer)> flagCoercers;
    Map<String,Anything({String*})> optionCoercers;
    Map<String,Anything({String+})> parameterCoercers;
    
    //value attrs = rootCommand.getAttributes;
    //Object instance = rootCommand(1, 2);
    
    value blah = `class CommandAbc`;
    for (parameterDeclaration in blah.parameterDeclarations) {
        parameterDeclaration.
    }
    
    
    
    /*
     Works something like this:
     - Look at commandFunc's flag/option/parameter annotated parameters
     - Probably all the parameters of the function need to be annotated
     - Know from those the argument name, and additional validity things from other annotations
     - Also know the destination type of the annotated parameter!
     - Before parsing rawArguments, check that there is a coercer that can work for the
       flag/option/parameter: an annotation can hint the name of the coercer?
     - Parse the arguments
     - Call the commandFunc with coerced arguments given to the function parameters
     - ?? how to handle subcommands (each needs a commandFunc)??
     */
    
    return nothing;
}

shared void parseWithExit() {
}

void etghrthr() {
    parse(`CommandAbc`);
}


///
///
///
///
///
///
///
///
///
///
///

class Test() {
    value cli = Cli.parseWithExit();
    
    shared Integer moshimoshi = cli.flag {
        name = "moshimoshi";
        validator = (Integer count) => count;
    };
    
    shared String hej = cli.optional {
        name = "hej";
        validator = ({String*} values) => "".join(values);
    };
}

class Test2() {
    ArgumentMatches asd = nothing;
    shared Integer qwe = asd.flag("", (s) => nothing);
    switch (asd.subcommand)
    case (is Null) {}
    case (is [String, ArgumentMatches]) {}
}

shared class ArgumentMatches(flags, options, parameters, subcommand) {
    shared Map<String,Integer> flags;
    shared Map<String,{String*}> options;
    shared Map<String,{String+}> parameters;
    shared [String, ArgumentMatches]? subcommand;
    
    shared Result flag<Result>(name, validator) {
        String name;
        Result(Integer) validator;
        return nothing;
    }
    
    shared Result option<Result>(name, validator) {
        String name;
        Result({String*}) validator;
        return nothing;
    }
    
    shared Result parameter<Result>(name, validator) {
        String name;
        Result({String+}) validator;
        return nothing;
    }
    
    shared ArgumentMatches subcommandMatches(name) {
        String name;
        if (exists subcommand, subcommand[0] == name) {
            return subcommand[1];
        } else {
            // TODO exit
            return nothing;
        }
    }
    
    shared Result|ParseError flagNoExit<Result>(name, validator) {
        String name;
        Result(Integer) validator;
        return nothing;
    }
    
    shared Result|ParseError optionNoExit<Result>(name, validator) {
        String name;
        Result({String*}) validator;
        return nothing;
    }
    
    shared Result|ParseError parameterNoExit<Result>(name, validator) {
        String name;
        Result({String+}) validator;
        return nothing;
    }
    
    shared ArgumentMatches|ParseError subcommandMatchesNoExit(name) {
        String name;
        if (exists subcommand, subcommand[0] == name) {
            return subcommand[1];
        } else {
            // TODO ParseError
            return nothing;
        }
    }
}

shared class Cli {
    shared new parse({String*} rawArguments = process.arguments) {
    }
    
    shared new parseWithExit({String*} rawArguments = process.arguments) {
    }
    
    shared Result flag<Result>(
        name,
        validator,
        short = null,
        long = null,
        help = "",
        conflictsWith = empty,
        overridesWith = empty,
        requires = empty,
        inheritable = false,
        hidden = false) {
        String name;
        Result(Integer) validator;
        Character? short;
        "By default long is equal to [[name]]"
        String? long;
        String help;
        {String*} conflictsWith;
        {String*} overridesWith;
        {String*} requires;
        Boolean inheritable;
        Boolean hidden;
        return nothing;
    }
    
    shared Result optional<Result>(
        name,
        validator,
        short = null,
        long = null,
        help = "",
        conflictsWith = empty,
        overridesWith = empty,
        requires = empty,
        inheritable = false,
        hidden = false,
        delimiter = null,
        valueNames = empty) {
        String name;
        Result({String*}) validator;
        Character? short;
        "By default long is equal to [[name]]"
        String? long;
        String help;
        {String*} conflictsWith;
        {String*} overridesWith;
        {String*} requires;
        Boolean inheritable;
        Boolean hidden;
        Character? delimiter;
        {String*} valueNames;
        return nothing;
    }
    
    shared Result positional<Result>(
        name,
        validator,
        short = null,
        long = null,
        help = "",
        conflictsWith = empty,
        overridesWith = empty,
        requires = empty,
        inheritable = false,
        hidden = false) {
        String name;
        Result({String+}) validator;
        Character? short;
        "By default long is equal to [[name]]"
        String? long;
        String help;
        {String*} conflictsWith;
        {String*} overridesWith;
        {String*} requires;
        Boolean inheritable;
        Boolean hidden;
        return nothing;
    }
}
