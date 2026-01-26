# LocalChat

**One chat app for all your AI models — local and hosted.**

LocalChat is a native iOS app that brings together the world's best AI models in a single, beautifully designed interface. Chat with cloud-hosted models like GPT, Claude, Gemini, and Grok, or keep things private with on-device Apple Intelligence — all from one app.

---

## ✨ Features

### 🤖 Multi-Provider Support
Access AI models from all major providers through a unified interface:

| Provider | Models | Type |
|----------|--------|------|
| **OpenAI** | GPT-5.2, GPT-5.2 Instant | Cloud (via OpenRouter) |
| **Anthropic** | Claude Sonnet 4.5, Claude Opus 4.5 | Cloud (via OpenRouter) |
| **Google** | Gemini 3 Pro, Gemini 3 Flash | Cloud (via OpenRouter) |
| **xAI** | Grok 4, Grok 4 Fast | Cloud (via OpenRouter) |
| **Perplexity** | Sonar Pro, Sonar Reasoning Pro | Cloud (Direct API) |
| **Apple** | Apple Intelligence | On-Device |

### 🔐 Privacy-First
- **On-Device AI**: Use Apple Intelligence for completely private, offline conversations
- **Secure Key Storage**: API keys are stored securely in the iOS Keychain
- **No Data Collection**: Your conversations stay on your device

### 💬 Rich Chat Experience
- **Streaming Responses**: See AI responses as they're generated in real-time
- **Markdown Rendering**: Full support for formatted text, code blocks, and more
- **Conversation History**: All chats are saved locally with SwiftData
- **Star Important Chats**: Pin your favorite conversations for quick access

### 🎨 Beautiful Design
- **Native iOS UI**: Built with SwiftUI for a smooth, responsive experience
- **Dark & Light Mode**: Automatic theme switching based on system preferences
- **Custom Sidebar Navigation**: Swipe-based navigation with smooth animations
- **Provider-Specific Branding**: Each AI model features its distinct visual identity

### ⚙️ Flexible Configuration
- **Model Store**: Browse and select from a curated catalog of AI models
- **Custom Endpoints**: Add your own OpenAI-compatible API endpoints
- **Per-Chat Settings**: Customize system prompts and parameters for each conversation
- **Default Preferences**: Set your preferred model and default chat settings

---

## 🛠 Requirements

- **iOS 26.0+** (for Apple Intelligence support)
- **Xcode 16+**
- **Swift 6**

---

## 🚀 Getting Started

### 1. Clone the Repository
```bash
git clone https://github.com/yourusername/LocalChat.git
cd LocalChat
```

### 2. Open in Xcode
```bash
open LocalChat.xcodeproj
```

### 3. Configure API Keys
Launch the app and navigate to **Settings** to add your API keys:

- **OpenRouter API Key** — For access to GPT, Claude, Gemini, and Grok models
- **Perplexity API Key** — For Sonar search-augmented models

> [!TIP]
> Apple Intelligence requires no API key and works entirely on-device.

### 4. Build & Run
Select your target device or simulator and hit **⌘R** to run.

---

## 🏗 Architecture

```
LocalChat/
├── LocalChatApp.swift       # App entry point & SwiftData configuration
├── ContentView.swift        # Main navigation & sidebar
├── Models/
│   ├── AIModel.swift        # AI model representation
│   ├── Chat.swift           # Chat entity (SwiftData)
│   ├── Message.swift        # Message entity (SwiftData)
│   └── StoreModel.swift     # Model Store catalog
├── Services/
│   ├── AIService.swift      # Main AI orchestration service
│   ├── ChatStore.swift      # Chat persistence & management
│   ├── KeychainService.swift# Secure API key storage
│   └── Providers/
│       ├── AIProvider.swift          # Provider protocol
│       ├── OpenRouterProvider.swift  # OpenRouter integration
│       ├── PerplexityProvider.swift  # Perplexity integration
│       ├── FoundationModelsProvider.swift # Apple Intelligence
│       └── CustomEndpointProvider.swift   # Custom API support
├── Views/
│   ├── ChatDetailView.swift # Individual chat interface
│   ├── NewChatView.swift    # Chat list & creation
│   ├── ModelStoreView.swift # Model browsing & selection
│   ├── SettingsView.swift   # App configuration
│   └── ...
└── Theme/
    └── AppTheme.swift       # Colors & styling
```

---

## 🔑 API Providers

### OpenRouter
[OpenRouter](https://openrouter.ai) provides unified access to models from OpenAI, Anthropic, Google, xAI, Meta, and more through a single API.

1. Create an account at [openrouter.ai](https://openrouter.ai)
2. Generate an API key
3. Add the key in LocalChat Settings

### Perplexity
[Perplexity](https://perplexity.ai) offers search-augmented AI models with real-time web access.

1. Sign up at [perplexity.ai](https://perplexity.ai)
2. Navigate to API settings and create a key
3. Add the key in LocalChat Settings

### Apple Intelligence
Apple Intelligence runs entirely on-device using Apple's Foundation Models framework. No API key or internet connection required.

> [!NOTE]
> Apple Intelligence requires iOS 26+ and a device with Apple Silicon.

### Custom Endpoints
Add any OpenAI-compatible API endpoint:

1. Go to **Settings → Custom Endpoints**
2. Tap **Add Endpoint**
3. Enter the base URL, model ID, and API key

---

## 📱 Screenshots

*Coming soon*

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- Built with [SwiftUI](https://developer.apple.com/xcode/swiftui/) and [SwiftData](https://developer.apple.com/xcode/swiftdata/)
- AI integrations powered by [OpenRouter](https://openrouter.ai) and [Perplexity](https://perplexity.ai)
- Icons from [SF Symbols](https://developer.apple.com/sf-symbols/)

---

<p align="center">
  <strong>Made with ❤️ by Carl</strong>
</p>
