package com.devops.demo.controller;

import com.devops.demo.model.User;
import com.devops.demo.service.UserService;
import com.devops.demo.repository.UserRepository;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@CrossOrigin(origins = "*")   // ✅ Frontend public EC2 ke liye
@RestController
@RequestMapping("/api")
public class UserController {

    private final UserRepository userRepository;
    private final UserService userService;   // ✅ Added for caching

    // ✅ Constructor Injection (Best Practice)
    public UserController(UserRepository userRepository, UserService userService) {
        this.userRepository = userRepository;
        this.userService = userService;
    }

    // ✅ Save user in MySQL
    @PostMapping("/register")
    public User register(@RequestBody User user) {
        return userRepository.save(user);
    }

    // ✅ Fetch all users from MySQL with Redis caching
    @GetMapping("/users")
    public List<User> getUsers() {
        return userService.getAllUsers();  // ✅ Cached
    }
}