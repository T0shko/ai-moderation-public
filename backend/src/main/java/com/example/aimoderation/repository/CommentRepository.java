package com.example.aimoderation.repository;

import com.example.aimoderation.model.Comment;
import com.example.aimoderation.model.CommentStatus;
import com.example.aimoderation.model.User;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface CommentRepository extends JpaRepository<Comment, Long> {
    List<Comment> findByStatus(CommentStatus status);

    List<Comment> findByAuthor(User author);
}
