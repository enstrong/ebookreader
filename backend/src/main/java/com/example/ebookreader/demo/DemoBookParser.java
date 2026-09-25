package com.example.ebookreader.demo;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.*;
import java.util.zip.*;
import javax.xml.XMLConstants;
import javax.xml.parsers.DocumentBuilderFactory;
import org.w3c.dom.*;

/** Text-only import: no uploaded HTML, scripts, external entities, or files are served. */
public final class DemoBookParser {
    public record Part(String title, String text) {}
    public record Parsed(String title, String author, List<Part> chapters) {}
    private static final int MAX_EXPANDED = 8 * 1024 * 1024;

    public static Parsed parse(String filename, byte[] bytes) throws Exception {
        String lower = filename.toLowerCase(Locale.ROOT);
        String title = filename.replaceFirst("\\.[^.]+$", "");
        if (lower.endsWith(".txt")) {
            String text = new String(bytes, StandardCharsets.UTF_8).replace("\u0000", "").strip();
            if (text.isBlank() || bytes.length > MAX_EXPANDED) throw new IOException("Empty or oversized text");
            List<Part> parts = new ArrayList<>();
            for (int start=0; start<text.length(); start+=20000) {
                parts.add(new Part("Part " + (parts.size()+1), text.substring(start, Math.min(text.length(), start+20000))));
            }
            return new Parsed(title, "Your upload", parts);
        }
        if (lower.endsWith(".fb2")) {
            Document doc = xml(bytes);
            NodeList sections = doc.getElementsByTagNameNS("*", "section");
            List<Part> parts = new ArrayList<>();
            for (int i=0; i<sections.getLength() && i<200; i++) {
                Element section = (Element) sections.item(i);
                if (section.getElementsByTagNameNS("*", "section").getLength() == 0) {
                    parts.add(new Part(first(section, "title", "Chapter " + (i+1)), text(section)));
                }
            }
            if (parts.isEmpty()) throw new IOException("No readable chapters");
            return new Parsed(first(doc.getDocumentElement(), "book-title", title),
                    first(doc.getDocumentElement(), "first-name", "") + " " + first(doc.getDocumentElement(), "last-name", ""), parts);
        }
        if (!lower.endsWith(".epub")) throw new IOException("Choose an EPUB, FB2, or UTF-8 TXT book");
        Map<String, byte[]> files = new HashMap<>();
        int total=0;
        try (ZipInputStream zip = new ZipInputStream(new ByteArrayInputStream(bytes))) {
            ZipEntry entry;
            while ((entry=zip.getNextEntry()) != null) {
                if (entry.isDirectory()) continue;
                if (files.size() >= 500) throw new IOException("Too many EPUB entries");
                byte[] data = zip.readNBytes(MAX_EXPANDED-total+1);
                total += data.length;
                if (total > MAX_EXPANDED) throw new IOException("Expanded EPUB exceeds 8 MB");
                files.put(entry.getName(), data);
            }
        }
        Document container = xml(require(files, "META-INF/container.xml"));
        Element rootfile = (Element) container.getElementsByTagNameNS("*", "rootfile").item(0);
        if (rootfile == null) throw new IOException("Invalid EPUB container");
        String opfPath = rootfile.getAttribute("full-path");
        Document opf = xml(require(files, opfPath));
        Path directory = Path.of(opfPath).getParent();
        Map<String,String> manifest = new HashMap<>();
        NodeList items=opf.getElementsByTagNameNS("*", "item");
        for (int i=0;i<items.getLength();i++) {
            Element item=(Element)items.item(i);
            String href = java.net.URLDecoder.decode(item.getAttribute("href").replace("+", "%2B"), StandardCharsets.UTF_8);
            String path=(directory == null ? Path.of(href) : directory.resolve(href)).normalize().toString();
            manifest.put(item.getAttribute("id"), path);
        }
        List<Part> parts = new ArrayList<>();
        NodeList spine=opf.getElementsByTagNameNS("*", "itemref");
        if (spine.getLength()>200) throw new IOException("Too many chapters");
        for (int i=0;i<spine.getLength();i++) {
            String path=manifest.get(((Element)spine.item(i)).getAttribute("idref"));
            Document chapter=xml(require(files,path));
            Element body=(Element)chapter.getElementsByTagNameNS("*","body").item(0);
            if (body==null) body=chapter.getDocumentElement();
            String content=text(body).strip();
            if (!content.isEmpty()) parts.add(new Part(first(body,"h1",first(body,"h2","Chapter "+(parts.size()+1))),content));
        }
        if (parts.isEmpty()) throw new IOException("No readable chapters");
        return new Parsed(first(opf.getDocumentElement(),"title",title), first(opf.getDocumentElement(),"creator","Your upload"),parts);
    }
    private static byte[] require(Map<String,byte[]> files,String name) throws IOException {
        byte[] bytes=files.get(name); if(bytes==null) throw new IOException("Incomplete EPUB"); return bytes;
    }
    private static Document xml(byte[] bytes) throws Exception {
        if(bytes.length>MAX_EXPANDED) throw new IOException("File exceeds 8 MB");
        // EPUB commonly declares an XHTML doctype. Accept it without loading its DTD,
        // but reject entity declarations and disable every external resource channel.
        if(new String(bytes,StandardCharsets.UTF_8).contains("<!ENTITY")) throw new IOException("Entity declarations are not allowed");
        var factory=DocumentBuilderFactory.newInstance(); factory.setNamespaceAware(true);
        factory.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING,true);
        factory.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd",false);
        factory.setFeature("http://xml.org/sax/features/external-general-entities",false);
        factory.setFeature("http://xml.org/sax/features/external-parameter-entities",false);
        factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD,"");
        factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA,"");
        factory.setXIncludeAware(false); factory.setExpandEntityReferences(false);
        return factory.newDocumentBuilder().parse(new ByteArrayInputStream(bytes));
    }
    private static String first(Element element,String tag,String fallback) {
        NodeList nodes=element.getElementsByTagNameNS("*",tag);
        return nodes.getLength()==0 ? fallback : nodes.item(0).getTextContent().strip();
    }
    private static String text(Node node) {
        if(node.getNodeType()==Node.TEXT_NODE) return node.getNodeValue();
        String name=node.getLocalName();
        if("script".equals(name)||"style".equals(name)) return "";
        StringBuilder result=new StringBuilder();
        for(Node child=node.getFirstChild();child!=null;child=child.getNextSibling()) result.append(text(child));
        if(Set.of("p","div","br","title","h1","h2","h3","section","stanza","v").contains(name==null?"":name)) result.append("\n\n");
        return result.toString();
    }
}
