# 📝 Exquisite Corpse (Cadavre Exquis) – Creative Writing App

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=flat&logo=Flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%230175C2.svg?style=flat&logo=Dart&logoColor=white)](https://dart.dev)
[![Open Source](https://img.shields.io/badge/Open%20Source-%E2%9D%A4-brightgreen.svg)](https://opensource.org/)

A cross-platform (iOS, Android, Web) application for **collaborative creative writing**, inspired by the famous surrealist game *Cadavre Exquis* (Exquisite Corpse). 

This project adapts the historical turn-based "blind" drawing dynamic into the realm of narrative fiction. It allows users to co-create unique stories consisting of an **Introduction, Development, and Epilogue**, without knowing the details of the segments written by other participants, except for small continuity hints.

---

## 🎲 The Concept

In the original paper game, each player draws a section of a creature (head, torso, legs), folding the paper to hide their contribution before passing it to the next person. 

This app translates that mechanic into text, establishing a pact of "creative blindness" between users to generate unpredictable, humorous, or surreal literary experiments.

### The Gameplay Loop (Story Flow)
The process unfolds across **3 main turns**:

1. **Phase 1: The Introduction (Author A)** The first player writes the opening of the story, setting up the characters or the initial context. They optionally leave a very short "hook phrase" visible for the next turn.
2. **Phase 2: The Development (Author B)** The second player, reading only the final line or the hint from the introduction, develops the core body of the story, building the action to its climax.
3. **Phase 3: The Epilogue (Author C)** The third player concludes the narrative, knowing only the final line of the development phase.
4. **The Reveal:** The complete story is assembled, displayed in its entirety to all participants, and saved to the community archive.

---

## 🛠️ Tech Stack & Architecture

The application is built using a modern, scalable, and performance-oriented ecosystem:

* **Framework:** [Flutter](https://flutter.dev) (Single codebase for Android, iOS, and Web).
* **Language:** [Dart](https://dart.dev) (Leveraging strong typing and asynchronous programming).
* **State Management:** *[e.g., Riverpod / BLoC]* For a reactive, predictable, and clean turn-management state.
* **Architecture:** Clean Architecture / Layered Architecture (Data, Domain, Presentation) to guarantee high maintainability and straightforward testing workflows.

---

## 🚀 Key Features (Roadmap)

- [ ] **Public & Private Lobbies:** Create custom rooms to play with friends via code, or join random matchmaking.
- [ ] **Minimalist Text Editor:** A distraction-free writing interface with an optional timer to stimulate flow of consciousness.
- [ ] **"Folded Paper" Logic:** Text obfuscation system that only displays the final words or tokens of the previous turn to guarantee a minimal logical link.
- [ ] **Story Showcase Feed:** A public wall to read, rate, and share the most successful and absurd "Exquisite Corpses".
- [ ] **Pass-and-Play (Local Offline Mode):** Play locally with friends using a single mobile device passed around.

---

## 🤝 Contributing

This project is fully **Open Source** and warmly welcomes contributions of any kind: feature development, code refactoring, UI/UX improvements, bug fixes, or documentation.

To get started:
1. **Fork** the repository.
2. Create a feature branch (`git checkout -b feature/AmazingFeature`).
3. **Commit** your changes (`git commit -m 'Add some AmazingFeature'`).
4. **Push** to the branch (`git push origin feature/AmazingFeature`).
5. Open a **Pull Request**.

---

## 📄 License

This project is licensed under the MIT License - see the `LICENSE` file for details.
