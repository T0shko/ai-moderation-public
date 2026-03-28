package com.example.aimoderation.repository;

import com.example.aimoderation.model.AiSettings;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface AiSettingsRepository extends JpaRepository<AiSettings, Long> {
    Optional<AiSettings> findFirstByOrderByIdAsc();
}
