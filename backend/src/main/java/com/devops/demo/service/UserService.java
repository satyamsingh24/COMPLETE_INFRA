package com.devops.demo.service;

import com.devops.demo.model.User;
import com.devops.demo.repository.UserRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class UserService {

    @Autowired
    private UserRepository userRepository;

    // ✅ Ye method cache karega 'users' key me
    @Cacheable(value = "users")
    public List<User> getAllUsers() {
        System.out.println("Fetching from DB..."); // debug
        return userRepository.findAll();
    }
}