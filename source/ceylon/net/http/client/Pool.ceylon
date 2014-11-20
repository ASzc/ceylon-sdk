import java.util.concurrent.locks {
    ReentrantLock
}
shared class PoolManager(maximumPools = 5) {
    Integer maximumPools;
    
    ReentrantLock lock = ReentrantLock();
    
}

shared PoolManager defaultPoolManager = PoolManager();

class HttpPool() {
}

class HttpsPool() {
}
