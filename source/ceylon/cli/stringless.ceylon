shared object helpText {
    // Others available for people constructing their own help text
    
    shared String standardAuthors(Command2 command) {
        return nothing;
    }
    
    shared String standardAbout(Command2 command) {
        return nothing;
    }
    
    // These three are those normally called as entrypoints to helptext
    
    shared String standardVersion(Command2 command) {
        return nothing;
    }
    
    shared String standardUsage(Command2 command) {
        return nothing;
    }
    
    shared String standardHelp(Command2 command) {
        return nothing;
    }
}

shared object flagActions {
    shared Boolean storeTrue(Boolean present) => present;
    shared Boolean storeFalse(Boolean present) => !present;
    shared Integer count(Integer count) => count;
}

// don't worry about tree-like neatness. avoid using strings to tie together
void sdfgsdfh() {
    value dgrd = FlagSingle(flagActions.storeTrue);
    // define all args here so they can cross reference based on value and not string id/name
    
    value rootcmd = Application2 {
        arguments = {
            dgrd
        };
    };
    rootcmd.parseWithExit();
    // After here all Argument.result have been initialized, except maybe those of non-active subcommands?
    
    if (dgrd.result) {
        
    }
}

shared abstract class Command2(arguments, subcommands=empty) {
    shared {Argument2<Anything>*} arguments;
    shared {Subcommand2*} subcommands;
    
    shared ParseError? parse() {
        for (argument in arguments) {
            if (is FlagSingle<Anything> argument) {
                argument.setResult(true);
            } else if (is FlagMultiple<Anything> argument) {
                argument.setResult(1);
            } else {
                throw AssertionError("Don't know Argument type ``argument``");
            }
        }
        return nothing;
    }
}
shared class Application2(arguments, subcommands)
        extends Command2(arguments, subcommands) {
    {Argument2<Anything>*} arguments;
    {Subcommand2*} subcommands;
    
    shared void parseWithExit() {
    }
}
shared class Subcommand2(arguments, subcommands)
        extends Command2(arguments, subcommands) {
    {Argument2<Anything>*} arguments;
    {Subcommand2*} subcommands;
}

shared abstract class Argument2<out Result>() {
    late shared Result result;
}
shared class FlagSingle<Result>(coerce)
        extends Argument2<Result>() {
    shared Result(Boolean) coerce;
    shared void setResult(Boolean c) => result = coerce(c);
}
shared class FlagMultiple<Result>(coerce, minTimes, maxTimes=null)
        extends Argument2<Result>() {
    shared Result(Integer) coerce;
    shared void setResult(Integer c) => result = coerce(c);
    shared Integer minTimes;
    shared Integer? maxTimes;
}
shared class OptionalSingle<Result>(coerce)
        extends Argument2<Result>() {
    Result(String?) coerce;
    shared void setResult(String? c) => result = coerce(c);
}
shared class OptionalMultiple<Result>(coerce, minTimes, maxTimes=null)
        extends Argument2<Result>() {
    Result({String*}) coerce;
    shared void setResult({String*} c) => result = coerce(c);
    shared Integer minTimes;
    shared Integer? maxTimes;
}
shared class PositionalSingle<Result>(coerce)
        extends Argument2<Result>() {
    Result(String) coerce;
    shared void setResult(String c) => result = coerce(c);
}
shared class PositionalMultiple<Result>(coerce, minTimes, maxTimes=null)
        extends Argument2<Result>() {
    Result({String+}) coerce;
    shared void setResult({String+} c) => result = coerce(c);
    shared Integer minTimes;
    shared Integer? maxTimes;
}
