"A [[Client]] with limited persistence between requests."
class Session(poolManager = PoolManager(), schemePorts = defaultSchemePorts)
        extends Client(poolManager, schemePorts) {
    "Used to get the sockets required for the requests."
    PoolManager poolManager;
    "Default ports for schemes. Used when a request URI doesn't specify a port value."
    Map<String,Integer> schemePorts;
    
    // TODO should offer cookie persistence, ability to set default headers to be applied to each request
}
