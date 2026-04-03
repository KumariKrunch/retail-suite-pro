# Contributing to Retail Suite Pro

Thanks for your interest in contributing to Retail Suite Pro! This guide will help you set up your development environment and understand our contribution workflow.

## Before You Start

- **Search first:** Check existing [issues](https://github.com/KumariKrunch/retail-suite-pro/issues) and [discussions](https://github.com/KumariKrunch/retail-suite-pro/discussions) before opening a new one.
- **Security vulnerabilities:** Do not open public issues for security vulnerabilities. Please email the maintainers privately.
- **Large features:** Open an issue or discussion first to discuss significant changes before investing time in implementation.

## Prerequisites

- **Rust toolchain** – Install from [rustup.rs](https://rustup.rs/) (1.70+)
- **Node.js** – v20+ or **Bun** v1.0+ for frontend tooling
- **Docker & Docker Compose** – For local database and infrastructure
- **PostgreSQL client tools** – `psql` (optional, for manual queries)
- **Make** – For task automation (`make` or `gmake`)
- **Git** – For version control

## Development Environment Setup

### 1. Clone and Initialize

```bash
git clone https://github.com/KumariKrunch/retail-suite-pro.git
cd retail-suite-pro
```

### 2. Start Infrastructure (Database, etc.)

```bash
docker-compose up -d
```

This starts PostgreSQL and any other required services defined in `docker-compose.yaml`.

### 3. Run Database Migrations

```bash
make migrate
# or manually:
psql -h localhost -U retail_user -d retail_db -f migrations/001_init.sql
```

### 4. Rust Backend Setup

The backend uses a Cargo workspace. Key directories:

- `crates/shared-kernel/` – Shared domain logic, utilities, and traits
- `services/store-api/` – Example API service

**Build and test all Rust code:**

```bash
cargo build          # Debug build
cargo build --release # Release build
cargo test           # Run all tests
cargo test --lib     # Unit tests only
```

**Format and lint Rust code:**

```bash
cargo fmt --all      # Format all code
cargo clippy --all   # Lint all code
```

Run these before committing Rust changes.

### 5. Frontend Setup

The frontend is in `services/store-ui/` and uses SvelteKit with Vite, TypeScript, and Tailwind CSS.

**Install dependencies:**

```bash
cd services/store-ui
npm install
# or with Bun:
bun install
```

**Start development server:**

```bash
npm run dev
# Visit http://localhost:5173
```

**Format and lint TypeScript/Svelte:**

```bash
npm run format       # Apply Prettier formatting
npm run lint         # Run ESLint checks
```

Run these before committing frontend changes.

**Run tests:**

```bash
npm run test:unit    # Vitest unit tests
npm run test:e2e     # Playwright e2e tests
npm run test         # Run both
```

## Project Structure

```
retail-suite-pro/
├── crates/
│   └── shared-kernel/          # Shared Rust domain logic
├── services/
│   ├── store-api/              # Backend Rust API service
│   └── store-ui/               # Frontend SvelteKit app
├── migrations/                 # PostgreSQL schema & migrations
├── docker-compose.yaml         # Local infrastructure
├── Makefile                    # Common development tasks
└── Cargo.toml                  # Rust workspace root
```

### Understanding the Workspace

- **Rust Crates** use a workspace model. Changes to `crates/shared-kernel/` affect all services that depend on it.
- **Frontend** is independent; changes to `services/store-ui/` don't require rebuilding backend services.

## Git & Pull Request Workflow

1. **Fork** the repository (if you don't have push access).
2. **Create a branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   # or for bug fixes:
   git checkout -b fix/your-bug-name
   ```

3. **Make your changes** and ensure tests pass locally:
   ```bash
   # For Rust changes:
   cargo fmt --all && cargo clippy --all && cargo test
   
   # For frontend changes:
   cd services/store-ui && npm run lint && npm run test
   ```

4. **Commit with clear messages:**
   ```bash
   git commit -m "feat: add product search API endpoint"
   git commit -m "fix: correct inventory count calculation"
   ```
   Use imperative mood and reference issue numbers when relevant.

5. **Push and open a PR:**
   ```bash
   git push origin feature/your-feature-name
   ```

6. **Fill out the PR template** with:
   - What the change does
   - Why it's needed
   - How to test it
   - Any breaking changes
   - Links to related issues

## Code Standards

### Rust

- Run `cargo fmt --all` before committing.
- Address all `cargo clippy --all` warnings.
- Write unit tests in the same file as your code.
- Follow [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/).

Example:

```rust
// Good: Clear, documented function
/// Calculates total cart price including tax
pub fn calculate_total(items: &[CartItem], tax_rate: f64) -> Result<f64, PricingError> {
    // implementation
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_calculate_total_with_valid_items() {
        // test logic
    }
}
```

### TypeScript / Svelte

- Run `npm run format` before committing (Prettier).
- Fix all `npm run lint` errors (ESLint).
- Use strict type checking (no `any` without justification).
- Follow the existing code style in `services/store-ui/`.

Example:

```svelte
<script lang="ts">
  import { page } from '$app/stores';

  interface Product {
    id: string;
    name: string;
    price: number;
  }

  let products: Product[] = $state([]);

  onMount(async () => {
    const res = await fetch('/api/products');
    products = await res.json();
  });
</script>

<h1>Products</h1>
{#each products as product (product.id)}
  <p>{product.name}: ${product.price}</p>
{/each}
```

## Database Changes

If your change modifies the database schema:

1. Create a new migration file in `migrations/`:
   ```
   migrations/002_add_user_preferences.sql
   ```

2. Include both `UP` and `DOWN` migrations if possible:
   ```sql
   -- UP
   ALTER TABLE users ADD COLUMN preferences JSONB DEFAULT '{}';
   
   -- DOWN
   ALTER TABLE users DROP COLUMN preferences;
   ```

3. Document schema changes in the PR.

4. Run locally and verify:
   ```bash
   make migrate  # or manual psql execution
   ```

## Testing Guidelines

### Rust

- Aim for >70% code coverage on new code.
- Write integration tests for critical paths (inventory, checkout, etc.).
- Use `#[tokio::test]` for async tests.

```bash
cargo tarpaulin --out Html  # Generate coverage report
```

### Frontend

- Write unit tests for utilities and components.
- Use Vitest for component tests, Playwright for e2e flows.

```bash
npm run test:unit     # Fast feedback during development
npm run test:e2e      # Full user journey tests
```

## Documentation

- **README.md** – Project overview (keep up-to-date).
- **Inline comments** – Explain *why*, not *what*; let code be self-documenting.
- **PR descriptions** – Context for reviewers and future maintainers.
- **Architecture decisions** – Add to `docs/` if significant.

## Commit Message Conventions

Use the following format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:** `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`

**Scope:** `store-api`, `store-ui`, `shared-kernel`, `migrations`, `infra`, etc.

**Examples:**

```
feat(store-api): add product search endpoint
fix(store-ui): correct cart total calculation
docs(README): update setup instructions
refactor(shared-kernel): extract pricing logic to module
```

## Release & Versioning

This project follows [Semantic Versioning](https://semver.org/):

- `MAJOR.MINOR.PATCH` (e.g., `1.2.3`)
- Breaking changes → `MAJOR` bump
- New features → `MINOR` bump
- Bug fixes → `PATCH` bump

Update `Cargo.toml` version fields when preparing a release.

## Common Tasks

```bash
# Start full local stack
docker-compose up -d

# Stop and clean up
docker-compose down

# View logs
docker-compose logs -f

# Run backend service
cargo run --bin store-api

# Run frontend dev server
cd services/store-ui && npm run dev

# Rebuild everything
cargo clean && cargo build --release

# Check for outdated dependencies
cargo outdated
npm outdated
```

## Troubleshooting

**Rust compilation fails:**
```bash
rustup update
cargo clean
cargo build
```

**Database connection issues:**
```bash
docker-compose ps           # Check container status
docker-compose logs -f db   # View database logs
make migrate                # Retry migrations
```

**Frontend build issues:**
```bash
rm -rf services/store-ui/node_modules services/store-ui/.svelte-kit
npm install
npm run build
```

## Need Help?

- Check existing [issues](https://github.com/KumariKrunch/retail-suite-pro/issues)
- Start a [discussion](https://github.com/KumariKrunch/retail-suite-pro/discussions)
- Review [Rust docs](https://doc.rust-lang.org/), [SvelteKit docs](https://kit.svelte.dev/), or [PostgreSQL docs](https://www.postgresql.org/docs/)

## Code of Conduct

- Be respectful and inclusive
- Assume good intent
- Welcome constructive feedback
- Help others learn

---

**Thank you for contributing to Retail Suite Pro!** 🎉 We appreciate your time and effort in making this e-commerce platform better.
