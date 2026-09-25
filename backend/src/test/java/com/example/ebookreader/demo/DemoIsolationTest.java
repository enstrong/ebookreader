package com.example.ebookreader.demo;

import com.example.ebookreader.model.*;
import com.example.ebookreader.repository.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import static org.assertj.core.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest(properties={"ebookreader.demo.enabled=true", "ebookreader.demo.seed-audiobook=false",
        "ebookreader.demo.seed-supplemental-catalog=false", "ebookreader.demo.cleanup-ms=99999999", "spring.jpa.show-sql=false"})
@ActiveProfiles("test")
@AutoConfigureMockMvc
class DemoIsolationTest {
    @Autowired MockMvc mvc;
    @Autowired ObjectMapper mapper;
    @Autowired BookRepository books;
    @Autowired ChapterRepository chapters;
    @Autowired UserRepository users;
    @Autowired JdbcTemplate db;
    @Autowired DemoSessions sessions;

    @Test
    void visitorsAreSeededIsolatedRevokedAndCleanedUp() throws Exception {
        Book sample=new Book(); sample.setTitle("Sample"); sample.setAuthor("Author");
        sample.setGoodreadsId("269322"); sample.setAvailability(BookAvailability.TEXT); books.save(sample);
        Chapter chapter=new Chapter(); chapter.setBook(sample); chapter.setChapterOrder(1);
        chapter.setContent("Once upon a midnight dreary, while I pondered, weak and weary."); chapters.save(chapter);
        String a=create(), b=create();
        mvc.perform(get("/api/user/profile")).andExpect(status().isForbidden());
        mvc.perform(get("/api/demo/session").header("Authorization","Bearer broken")).andExpect(status().isUnauthorized());
        mvc.perform(post("/graphql").contentType(MediaType.APPLICATION_JSON).content("{\"query\":\"mutation { deleteBook(id: 1) }\"}"))
                .andExpect(status().isNotFound());
        mvc.perform(post("/api/auth/register")).andExpect(status().isNotFound());
        var seeded=mapper.readTree(mvc.perform(get("/api/user/books/"+sample.getId()+"/annotations").header("Authorization",a))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
        assertThat(seeded.size()).isEqualTo(1);
        var file=new MockMultipartFile("file","private.txt","text/plain","My private uploaded book.".getBytes(StandardCharsets.UTF_8));
        var imported=mapper.readTree(mvc.perform(multipart("/api/demo/uploads").file(file).header("Authorization",a))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
        long id=imported.get("id").asLong();
        mvc.perform(get("/api/books/"+id).header("Authorization",a)).andExpect(status().isOk());
        mvc.perform(get("/api/books/"+id).header("Authorization",b)).andExpect(status().isNotFound());
        mvc.perform(get("/api/books/"+id)).andExpect(status().isNotFound());
        var hidden=mapper.readTree(mvc.perform(get("/api/books/"+id+"/chapters").header("Authorization",b))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
        assertThat(hidden.size()).isZero();
        mvc.perform(put("/api/user/books/"+sample.getId()+"/rating").header("Authorization",a)
                .contentType(MediaType.APPLICATION_JSON).content("{\"rating\":2}")).andExpect(status().isOk());
        var bProfile=mapper.readTree(mvc.perform(get("/api/user/profile").header("Authorization",b))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
        String bName=bProfile.path("nickname").asText();
        long bId=users.findByNickname(bName).orElseThrow().getId();
        assertThat(db.queryForObject("select rating from user_books where user_id=? and book_id=?",Integer.class,bId,sample.getId())).isEqualTo(5);
        mvc.perform(delete("/api/demo/session").header("Authorization",a)).andExpect(status().isNoContent());
        mvc.perform(get("/api/user/profile").header("Authorization",a)).andExpect(status().isUnauthorized());
        assertThat(books.findById(id)).isEmpty();
        assertThat(db.queryForObject("select count(*) from demo_uploads",Long.class)).isZero();
        db.update("update users set demo_expires_at=? where id=?",java.sql.Timestamp.from(Instant.now().minusSeconds(1)),bId);
        mvc.perform(get("/api/user/profile").header("Authorization",b)).andExpect(status().isUnauthorized());
        sessions.cleanup();
        assertThat(users.findById(bId)).isEmpty();
        assertThat(books.findById(sample.getId())).isPresent();
    }
    private String create() throws Exception {
        return "Bearer "+mapper.readTree(mvc.perform(post("/api/demo/session")).andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString()).get("token").asText();
    }
}
