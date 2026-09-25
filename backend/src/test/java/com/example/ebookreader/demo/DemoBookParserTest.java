package com.example.ebookreader.demo;

import org.junit.jupiter.api.Test;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.zip.*;
import static org.assertj.core.api.Assertions.*;

class DemoBookParserTest {
    @Test void importsTxtAndFb2AndEpubInSpineOrder() throws Exception {
        assertThat(DemoBookParser.parse("hello.txt","Hello world".getBytes()).chapters().get(0).text()).isEqualTo("Hello world");
        String fb2="<FictionBook><description><title-info><book-title>Test</book-title></title-info></description><body><section><title>One</title><p>Readable words</p></section></body></FictionBook>";
        assertThat(DemoBookParser.parse("book.fb2",fb2.getBytes()).chapters().get(0).text()).contains("Readable words");
        ByteArrayOutputStream out=new ByteArrayOutputStream();
        try(ZipOutputStream zip=new ZipOutputStream(out)) {
            add(zip,"META-INF/container.xml","<container><rootfiles><rootfile full-path='OEBPS/content.opf'/></rootfiles></container>");
            add(zip,"OEBPS/content.opf","<package><metadata><title>EPUB test</title></metadata><manifest><item id='b' href='second.xhtml'/><item id='a' href='first.xhtml'/></manifest><spine><itemref idref='a'/><itemref idref='b'/></spine></package>");
            add(zip,"OEBPS/second.xhtml","<html><body><p>Second chapter</p></body></html>");
            add(zip,"OEBPS/first.xhtml","<!DOCTYPE html PUBLIC '-//W3C//DTD XHTML 1.1//EN' 'http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd'><html><body><p>First chapter</p><script>alert(1)</script></body></html>");
        }
        var book=DemoBookParser.parse("book.epub",out.toByteArray());
        assertThat(book.chapters()).hasSize(2);
        assertThat(book.chapters().get(0).text()).contains("First chapter").doesNotContain("alert");
    }
    @Test void rejectsExternalEntitiesAndZipBombs() throws Exception {
        String xxe="<!DOCTYPE x [<!ENTITY xxe SYSTEM 'file:///etc/passwd'>]><FictionBook><body><section><p>&xxe;</p></section></body></FictionBook>";
        assertThatThrownBy(()->DemoBookParser.parse("book.fb2",xxe.getBytes())).isInstanceOf(Exception.class);
        ByteArrayOutputStream out=new ByteArrayOutputStream();
        try(ZipOutputStream zip=new ZipOutputStream(out)) {
            zip.putNextEntry(new ZipEntry("bomb")); zip.write(new byte[9*1024*1024]); zip.closeEntry();
        }
        assertThatThrownBy(()->DemoBookParser.parse("book.epub",out.toByteArray())).hasMessageContaining("exceeds");
    }
    private static void add(ZipOutputStream zip,String path,String content) throws IOException {
        zip.putNextEntry(new ZipEntry(path)); zip.write(content.getBytes(StandardCharsets.UTF_8)); zip.closeEntry();
    }
}
