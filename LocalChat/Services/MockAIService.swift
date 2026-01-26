//
//  MockAIService.swift
//  LocalChat
//
//  Created by Carl Steen on 19.01.26.
//

import Foundation

actor MockAIService {
    
    private let mockResponses: [String] = [
        "That's a fascinating question! Let me think about this for a moment. In my experience, the key lies in understanding the underlying principles rather than just memorizing solutions. Would you like me to elaborate on any specific aspect?",
        "Great point! Here's what I think about this: The most effective approach combines both theoretical knowledge and practical application. The balance between these two often determines success in complex problem-solving scenarios.",
        "I appreciate you bringing this up. This is actually a topic I find quite interesting. There are multiple perspectives to consider here, and I'd be happy to walk you through the main ones if you're interested.",
        "Absolutely! Let me break this down into manageable parts. First, we need to understand the core concept. Then, we can explore how it applies to your specific situation. Finally, we can discuss potential solutions.",
        "That's an excellent observation. You've touched on something that many people overlook. The nuances here are important because they often determine the difference between a good solution and a great one.",
        "I see what you're getting at. This reminds me of a similar challenge where the solution involved thinking outside the conventional boundaries. Sometimes the best answers come from unexpected directions.",
        "You raise a valid point. The complexity of this topic means there's rarely a one-size-fits-all answer. However, I can share some general principles that tend to work well across different scenarios.",
        "Interesting! This is exactly the kind of question that requires careful consideration. Let me share my thoughts, but keep in mind that your specific context might require some adjustments to these ideas.",
        "I love questions like this because they push us to think deeper. The surface-level answer might seem straightforward, but there's often more nuance beneath. Shall we explore this together?",
        "That's a thought-provoking topic! In my analysis, there are several factors at play here. Understanding how they interact can help us arrive at a more comprehensive solution."
    ]
    
    func streamResponse(for input: String, onUpdate: @escaping (String) async -> Void) async {
        // Select a random response
        let response = mockResponses.randomElement() ?? mockResponses[0]
        
        // Simulate typing effect with variable delays
        var currentText = ""
        
        for character in response {
            currentText.append(character)
            
            await onUpdate(currentText)
            
            // Variable delay for more natural typing feel
            let delay: UInt64
            if character == "." || character == "!" || character == "?" {
                delay = UInt64.random(in: 200_000_000...400_000_000) // Longer pause at sentence end
            } else if character == "," {
                delay = UInt64.random(in: 100_000_000...200_000_000) // Medium pause at commas
            } else {
                delay = UInt64.random(in: 15_000_000...40_000_000) // Fast typing
            }
            
            try? await Task.sleep(nanoseconds: delay)
        }
    }
    
    func generateInstantResponse(for input: String) -> String {
        return mockResponses.randomElement() ?? mockResponses[0]
    }
}
