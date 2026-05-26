package com.example.ebookreader.repository;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import com.example.ebookreader.model.CommunityReaction;

@Repository
public interface CommunityReactionRepository extends JpaRepository<CommunityReaction, Long> {
    Optional<CommunityReaction> findByUserIdAndTargetTypeAndTargetId(Long userId, String targetType, Long targetId);
    List<CommunityReaction> findByTargetTypeAndTargetIdIn(String targetType, Collection<Long> targetIds);
    long countByTargetTypeAndTargetIdAndValue(String targetType, Long targetId, Integer value);
}
