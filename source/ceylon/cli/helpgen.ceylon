import ceylon.language.meta {
    annotations
}
import ceylon.language.meta.declaration {
    Module
}

/*
 * About
 */

shared String[] moduleAuthors(Module mod) {
    return if (exists a = annotations(`AuthorsAnnotation`, mod))
    then a.authors
    else empty;
}

shared String moduleDescription(Module mod) {
    return if (exists a = annotations(`DocAnnotation`, mod))
    then a.description
    else "";
}

"Create about text with [[verboseAbout]] using information from a module"
shared String(Command<Results,SubResults>) moduleAbout<Results,SubResults>(mod, authors = true, description = false) {
    Module mod;
    Boolean authors;
    Boolean description;
    return verboseAbout<Results,SubResults> {
        version = mod.version;
        authors = if (authors) then moduleAuthors(mod) else empty;
        description = if (description) then moduleDescription(mod) else "";
    };
}

"""
   Create about text in the form:
   
   ```plain
   matrix 1.0
   Thomas A. Anderson <tanderson@metacortex.com>
   Virtual Reality
   ```
   
   i.e.
   ```plain
   {inital} {version}
   {author}
   ...
   {description}
   ```
   
   from the given [[version]], [[authors]] and [[description]] text.
   [[minimalAbout]] provides the initial text.
   """
shared String verboseAbout<Results,SubResults>
        (String version, {String*} authors, String description)
        (Command<Results,SubResults> command) {
    String initial = minimalAbout<Results,SubResults>(command);
    return String(
        initial.chain(" ").chain(version).chain("\n")
            .chain("".join(authors)).chain("\n")
            .chain(description).chain("\n")
    );
}

"Return [[Command.name]]"
shared String minimalAbout<Results,SubResults>(Command<Results,SubResults> command) {
    return command.name;
}

/*
 * Usage
 */

shared String standardUsage<Results,SubResults>(Command<Results,SubResults> command) {
    return nothing;
}

/*
 * Help
 */

shared String standardHelp<Results,SubResults>(Command<Results,SubResults> command) {
    return nothing;
}

see (`function moduleDescription`)
shared String standardHelpWithDescription<Results,SubResults>
        (String before = "", String after = "")
        (Command<Results,SubResults> command) {
    return nothing;
}
