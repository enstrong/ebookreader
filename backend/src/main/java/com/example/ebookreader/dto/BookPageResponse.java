package com.example.ebookreader.dto;

import java.util.List;

import com.example.ebookreader.model.Book;

public class BookPageResponse {
    private List<Book> items;
    private int page;
    private int size;
    private long totalItems;
    private int totalPages;
    private boolean hasNext;

    public BookPageResponse(List<Book> items, int page, int size, long totalItems, int totalPages, boolean hasNext) {
        this.items = items;
        this.page = page;
        this.size = size;
        this.totalItems = totalItems;
        this.totalPages = totalPages;
        this.hasNext = hasNext;
    }

    public List<Book> getItems() { return items; }
    public void setItems(List<Book> items) { this.items = items; }

    public int getPage() { return page; }
    public void setPage(int page) { this.page = page; }

    public int getSize() { return size; }
    public void setSize(int size) { this.size = size; }

    public long getTotalItems() { return totalItems; }
    public void setTotalItems(long totalItems) { this.totalItems = totalItems; }

    public int getTotalPages() { return totalPages; }
    public void setTotalPages(int totalPages) { this.totalPages = totalPages; }

    public boolean isHasNext() { return hasNext; }
    public void setHasNext(boolean hasNext) { this.hasNext = hasNext; }
}
