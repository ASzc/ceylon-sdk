shared class ArgumentGroup(
    name,
    members,
    required,
    requires,
    conflicts) {
    "The name of this group. Can be any unique string."
    shared String name;
    "Names of arguments that are a part of this group"
    shared {String*} members;
    "If true, exactly one argument within this group is required to be present,
     except when conflicting."
    shared Boolean required;
    "Names of arguments or argument groups that are required by this group"
    shared {String*} requires;
    "Names of arguments or argument groups that conflict with this group"
    shared {String*} conflicts;
}
