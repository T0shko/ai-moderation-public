package com.example.aimoderation.repository;

import com.example.aimoderation.model.ModerationTrainingData;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface ModerationTrainingDataRepository extends JpaRepository<ModerationTrainingData, Long> {
}
