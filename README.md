# Retail Suite Pro 🛒

An open-source, high-performance e-commerce suite engineered by [KumariKrunch](https://github.com/KumariKrunch). Originally designed to power our direct-to-consumer platform for authentic, traditional Kanyakumari snacks, this suite provides a highly scalable foundation for modern digital retail.

## 🚀 Tech Stack

- **Backend:** Rust (Workspace-based micro-architecture)
- **Frontend:** Svelte & TypeScript
- **Database:** PostgreSQL (with PL/pgSQL)
- **Infrastructure:** Docker & Docker Compose

## 📁 Project Structure

The repository is structured to cleanly separate core domain logic from independent services:

- `crates/shared-kernel/`: Core domain logic, shared utilities, and foundational Rust traits used across the ecosystem.
- `services/`: Independent backend services handling specific bounded contexts (e.g., inventory, orders, checkout).
- `migrations/`: PostgreSQL schema definitions and database migration scripts.
- `docker-compose.yaml`: Container orchestration for local development and testing.

## 🛠️ Getting Started

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and Docker Compose
- [Rust toolchain](https://rustup.rs/) (Cargo)
- [Node.js](https://nodejs.org/) (for frontend tooling)
- `make`

### Local Development

1. **Clone the repository:**
   ```bash
   git clone [https://github.com/KumariKrunch/retail-suite-pro.git](https://github.com/KumariKrunch/retail-suite-pro.git)
   cd retail-suite-pro
   ```

2.  **Start the infrastructure (Database, etc.):**

    ```bash
    docker-compose up -d
    ```

3.  **Run database migrations:**

    ```bash
    make migrate
    ```

4.  **Build and run the backend:**

    ```bash
    cargo run --bin <service-name>
    ```

## 🤝 Contributing

We welcome contributions\! Whether you're fixing bugs, optimizing Rust crates, or refining the Svelte UI, please open an issue or submit a pull request.

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](https://www.google.com/search?q=LICENSE) file for details.
