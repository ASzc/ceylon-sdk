shared String passthroughValidator(String candidate) {
    return candidate;
}

shared abstract class Argument<out Result>()
//of Flag | Optional | Positional {
{
    shared formal Result result;
}

// could these be replaced with closures of Result()() ?

shared class Flag<Result>(
    name,
    validator,
    short = null,
    long = null,
    help = "",
    conflictsWith = empty,
    overridesWith = empty,
    requires = empty,
    inheritable = false,
    hidden = false)
        extends Argument<Result>() {
    String name;
    Character? short;
    "By default long is equal to [[name]]"
    String? long;
    String help;
    {String*} conflictsWith;
    {String*} overridesWith;
    {String*} requires;
    Boolean inheritable;
    Boolean hidden;
    
    "Param is the number of times the flag appeared"
    Result(Integer) validator;
    shared actual Result result => nothing;
}

shared class Optional<Result>(
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
    valueNames = empty)
        extends Argument<Result>() {
    String name;
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
    
    "Param is the zero or more raw values provided with instances of the option"
    Result({String*}) validator;
    shared actual Result result => nothing;
}

shared class Positional<Result>(
    name,
    validator,
    short = null,
    long = null,
    help = "",
    conflictsWith = empty,
    overridesWith = empty,
    requires = empty,
    inheritable = false,
    hidden = false)
        extends Argument<Result>() {
    String name;
    Character? short;
    "By default long is equal to [[name]]"
    String? long;
    String help;
    {String*} conflictsWith;
    {String*} overridesWith;
    {String*} requires;
    Boolean inheritable;
    Boolean hidden;
    
    "Param is the one or more raw values provided as instances of the positional"
    Result({String+}) validator;
    shared actual Result result => nothing;
}
