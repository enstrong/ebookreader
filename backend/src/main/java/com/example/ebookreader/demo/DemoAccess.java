package com.example.ebookreader.demo;

import com.example.ebookreader.model.Book;

/** Request identity for private uploads; cleared after every request. */
public final class DemoAccess {
    private record Viewer(Long id, boolean demo) {}
    private static final ThreadLocal<Viewer> CURRENT = new ThreadLocal<>();
    private DemoAccess() {}
    public static void enter(Long id, boolean demo) { CURRENT.set(new Viewer(id, demo)); }
    public static void clear() { CURRENT.remove(); }
    public static Long userId() { return CURRENT.get() == null ? null : CURRENT.get().id(); }
    public static boolean isDemo() { return CURRENT.get() != null && CURRENT.get().demo(); }
    public static boolean canRead(Book book) {
        return book.getDemoOwnerId() == null || book.getDemoOwnerId().equals(userId());
    }
    public static boolean canReadUser(Long id) { return !isDemo() || id.equals(userId()); }
}
