package com.example.ebookreader.model;

public enum BookAvailability {
    METADATA_ONLY,
    TEXT,
    AUDIO,
    SYNCED,
    PDF_ONLY;

    public boolean hasText() {
        return this == TEXT || this == SYNCED;
    }

    public boolean hasAudio() {
        return this == AUDIO || this == SYNCED;
    }

    public boolean isLibraryAvailable() {
        return hasText() || hasAudio();
    }
}
