package com.flow.systemtest;

import java.time.Duration;
import java.util.concurrent.Callable;
import org.awaitility.Awaitility;

public final class Eventually {
    private Eventually() {}

    public static void until(Duration timeout, Callable<Boolean> condition) {
        Awaitility.await().atMost(timeout).pollInterval(Duration.ofSeconds(1)).until(condition);
    }
}
