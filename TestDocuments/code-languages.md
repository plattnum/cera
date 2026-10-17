# Code in every language

One example per language Cera's syntax highlighting is meant to cover. Each is a real-looking method with a bit of everything a highlighter colors: line, block, and doc comments; strings with escapes and interpolation; numbers in several forms; keywords; types; function names and calls; constants like `true` and `nil`; annotations and attributes; generics; and operators. Switch themes to check every color in each one.

## Swift

```swift
import Foundation

/// Downloads and decodes a page of articles, retrying on failure.
/// - Parameter page: The page to load, starting at 1.
@MainActor
final class ArticleLoader<Decoder: TopLevelDecoder> where Decoder.Input == Data {
    private let session: URLSession
    private var cache: [Int: [Article]] = [:]
    static let maxRetries = 3

    init(session: URLSession = .shared) {
        self.session = session
    }

    func load(page: Int, retries: Int = ArticleLoader.maxRetries) async throws -> [Article] {
        if let cached = cache[page] { return cached } // Cache hit.
        let url = URL(string: "https://example.com/api/articles?page=\(page)&limit=\(20 * 2)")!
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw LoaderError.badStatus
            }
            let articles = try JSONDecoder().decode([Article].self, from: data)
            cache[page] = articles.filter { !$0.title.isEmpty && $0.score >= 0.5 }
            return cache[page] ?? []
        } catch where retries > 0 {
            try await Task.sleep(nanoseconds: 250_000_000)
            return try await load(page: page, retries: retries - 1)
        }
    }
}

enum LoaderError: Error { case badStatus, timeout(seconds: Double) }
let hex = 0xFF_00_FF, binary = 0b1010, ready: Bool? = nil
```

## Python

```python
from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from typing import Iterable


@dataclass(frozen=True)
class Order:
    """An order and its line items."""

    id: int
    items: list[tuple[str, float]] = field(default_factory=list)
    paid: bool = False

    def total(self, tax_rate: float = 0.07) -> float:
        subtotal = sum(price for _, price in self.items)
        return round(subtotal * (1 + tax_rate), 2)


async def summarize(orders: Iterable[Order], *, limit: int = 10) -> dict[str, object]:
    # Only paid orders count toward revenue.
    paid = [o for o in orders if o.paid and len(o.items) > 0]
    revenue = sum(o.total() for o in paid[:limit])
    await asyncio.sleep(0.1)
    if revenue == 0:
        raise ValueError(f"no revenue from {len(paid)} orders\n")
    return {"count": len(paid), "revenue": revenue, "big": revenue > 1e3, "note": None, "hex": 0x1F}


print(r"raw \d+ string", b"bytes", lambda x: x ** 2)
```

## JavaScript

```javascript
'use strict';

/**
 * Debounces a function: it runs once the calls stop for `wait` milliseconds.
 * @param {Function} fn
 * @param {number} [wait=200]
 */
export function debounce(fn, wait = 200) {
  let timer = null;
  return function debounced(...args) {
    clearTimeout(timer);
    timer = setTimeout(() => fn.apply(this, args), wait);
  };
}

class Store extends EventTarget {
  #state = { items: [], loading: false };

  async refresh(query) {
    this.#state.loading = true;
    try {
      const res = await fetch(`/api/search?q=${encodeURIComponent(query)}&n=${10 ** 2}`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const { items = [] } = await res.json();
      this.#state.items = items.filter((item) => item?.score >= 0.5 && item.id !== undefined);
    } catch (err) {
      console.error('refresh failed:', err.message, /timeout/i.test(err.message));
    } finally {
      this.#state.loading = false;
      this.dispatchEvent(new CustomEvent('change', { detail: { size: this.#state.items.length } }));
    }
  }
}

const hex = 0xff, big = 9007199254740993n, nothing = null;
```

## JSX

```jsx
import { useEffect, useState } from 'react';

// A list that loads its rows once and shows a count.
export default function TaskList({ userId, onSelect }) {
  const [tasks, setTasks] = useState([]);

  useEffect(() => {
    let cancelled = false;
    fetch(`/users/${userId}/tasks`)
      .then((res) => res.json())
      .then((data) => !cancelled && setTasks(data));
    return () => { cancelled = true; };
  }, [userId]);

  return (
    <section className="tasks" aria-busy={tasks.length === 0}>
      <h2>{tasks.length} tasks</h2>
      <ul>
        {tasks.map((task) => (
          <li key={task.id} onClick={() => onSelect(task)} data-done={task.done ? 'yes' : 'no'}>
            {task.done && <span className="check">✓</span>} {task.title}
          </li>
        ))}
      </ul>
    </section>
  );
}
```

## TypeScript

```typescript
import type { Request, Response } from 'express';

/** A paginated result. */
interface Page<T> {
  readonly items: T[];
  total: number;
  next?: string | null;
}

type Status = 'active' | 'archived';

enum Role { Admin = 1, Editor, Viewer }

@Controller('/projects')
export class ProjectService<T extends { id: number; status: Status }> {
  private readonly cache = new Map<number, T>();

  constructor(private readonly db: Database, public limit = 50) {}

  async list(req: Request, res: Response): Promise<Page<T>> {
    const page = Number.parseInt(String(req.query.page ?? '1'), 10);
    const rows = await this.db.query<T>(`SELECT * FROM projects LIMIT ${this.limit} OFFSET ${(page - 1) * this.limit}`);
    rows.forEach((row) => this.cache.set(row.id, row));
    const items = rows.filter((row): row is T => row.status !== 'archived');
    return { items, total: items.length, next: items.length === this.limit ? `?page=${page + 1}` : null };
  }
}

const role: Role = Role.Editor as const satisfies Role;
```

## TSX

```tsx
import React, { type FC, useMemo } from 'react';

type Props<Row> = {
  rows: Row[];
  columns: Array<keyof Row>;
  onRowClick?: (row: Row, index: number) => void;
};

// A small generic table.
export const DataTable = <Row extends Record<string, unknown>>({ rows, columns, onRowClick }: Props<Row>) => {
  const sorted = useMemo(() => [...rows].sort((a, b) => String(a[columns[0]]).localeCompare(String(b[columns[0]]))), [rows, columns]);

  return (
    <table className="data-table">
      <thead>
        <tr>{columns.map((c) => <th key={String(c)}>{String(c).toUpperCase()}</th>)}</tr>
      </thead>
      <tbody>
        {sorted.map((row, i) => (
          <tr key={i} onClick={() => onRowClick?.(row, i)} tabIndex={0}>
            {columns.map((c) => <td key={String(c)}>{String(row[c] ?? '—')}</td>)}
          </tr>
        ))}
      </tbody>
    </table>
  );
};

export const Empty: FC = () => <p className="empty">Nothing here yet.</p>;
```

## JSON

```json
{
  "name": "cera-sample",
  "version": "1.4.0",
  "private": true,
  "description": "Escapes: \"quoted\", tab\t, unicode \u00e9",
  "scripts": {
    "build": "tsc -p .",
    "test": "vitest run --coverage"
  },
  "limits": { "maxItems": 250, "ratio": 0.75, "threshold": -1.5e-3 },
  "tags": ["markdown", "editor", "macOS"],
  "homepage": null,
  "nested": [{ "id": 1, "ok": false }, { "id": 2, "ok": true }]
}
```

## Bash

```bash
#!/usr/bin/env bash
# Backs up a directory, keeping the newest N archives.
set -euo pipefail

readonly KEEP=${KEEP:-5}
SOURCE="${1:?usage: backup.sh <dir>}"
DEST="$HOME/backups/$(basename "$SOURCE")"

backup() {
  local stamp archive
  stamp=$(date +%Y-%m-%d_%H%M%S)
  archive="$DEST/$stamp.tar.gz"
  mkdir -p "$DEST"
  if tar -czf "$archive" -C "$(dirname "$SOURCE")" "$(basename "$SOURCE")" 2>/dev/null; then
    echo "Saved $archive ($(du -h "$archive" | cut -f1))"
  else
    echo "Backup of '$SOURCE' failed" >&2
    return 1
  fi
}

prune() {
  local count=0
  for file in $(ls -1t "$DEST"/*.tar.gz); do
    (( count += 1 ))
    [[ $count -gt $KEEP ]] && rm -f -- "$file"
  done
}

backup && prune || exit $?
cat <<EOF
Done: kept ${KEEP} archives in ${DEST}
EOF
```

## Rust

```rust
use std::collections::HashMap;
use std::fmt;

/// A word-frequency counter over borrowed text.
#[derive(Debug, Default, Clone)]
pub struct Counter<'a> {
    counts: HashMap<&'a str, usize>,
    total: u64,
}

impl<'a> Counter<'a> {
    pub fn feed(&mut self, text: &'a str) -> &mut Self {
        for word in text.split_whitespace().filter(|w| w.len() > 2) {
            *self.counts.entry(word).or_insert(0) += 1;
            self.total += 1;
        }
        self
    }

    /// The `n` most frequent words, most frequent first.
    pub fn top(&self, n: usize) -> Vec<(&'a str, usize)> {
        let mut pairs: Vec<_> = self.counts.iter().map(|(w, c)| (*w, *c)).collect();
        pairs.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0)));
        pairs.into_iter().take(n).collect()
    }
}

impl fmt::Display for Counter<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{} words, {} distinct\n", self.total, self.counts.len())
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let text = std::fs::read_to_string("notes.md")?;
    let mut counter = Counter::default();
    counter.feed(&text);
    match counter.top(3).as_slice() {
        [first, ..] if first.1 > 10 => println!("most common: {:?}", first),
        [] => eprintln!("empty"),
        other => println!("{other:?}"),
    }
    const LIMIT: u32 = 0xFF_FF; let ratio = 1.5e-3_f64; let _ok = true && !false;
    Ok(())
}
```

## Go

```go
package cache

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"
)

// ErrMissing is returned when a key isn't cached.
var ErrMissing = errors.New("cache: missing key")

// Cache is a small TTL cache safe for concurrent use.
type Cache[K comparable, V any] struct {
	mu    sync.RWMutex
	items map[K]entry[V]
	ttl   time.Duration
}

type entry[V any] struct {
	value   V
	expires time.Time
}

// New makes a cache whose entries live for ttl.
func New[K comparable, V any](ttl time.Duration) *Cache[K, V] {
	return &Cache[K, V]{items: make(map[K]entry[V], 64), ttl: ttl}
}

func (c *Cache[K, V]) Get(ctx context.Context, key K, load func(K) (V, error)) (V, error) {
	c.mu.RLock()
	e, ok := c.items[key]
	c.mu.RUnlock()
	if ok && time.Now().Before(e.expires) {
		return e.value, nil
	}
	select {
	case <-ctx.Done():
		var zero V
		return zero, fmt.Errorf("get %v: %w", key, ctx.Err())
	default:
	}
	v, err := load(key)
	if err != nil {
		return v, errors.Join(ErrMissing, err)
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.items[key] = entry[V]{value: v, expires: time.Now().Add(c.ttl)}
	return v, nil
}

const maxSize = 1 << 10 // 1024
var ratio, hex = 0.75, 0x1F
```

## C

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_LINE 1024
#define SQUARE(x) ((x) * (x))

/* A growable array of strings. */
typedef struct {
    char **items;
    size_t count, capacity;
} StringList;

static int list_push(StringList *list, const char *text) {
    if (list->count == list->capacity) {
        size_t next = list->capacity ? list->capacity * 2 : 8;
        char **grown = realloc(list->items, next * sizeof *grown);
        if (grown == NULL) return -1; // Out of memory.
        list->items = grown;
        list->capacity = next;
    }
    list->items[list->count++] = strdup(text);
    return 0;
}

int main(int argc, char *argv[]) {
    FILE *file = argc > 1 ? fopen(argv[1], "r") : stdin;
    if (!file) { perror("fopen"); return EXIT_FAILURE; }
    StringList lines = {0};
    char buffer[MAX_LINE];
    while (fgets(buffer, sizeof buffer, file) != NULL) {
        buffer[strcspn(buffer, "\r\n")] = '\0';
        if (list_push(&lines, buffer) != 0) break;
    }
    printf("%zu lines, last: \"%s\"\n", lines.count, lines.count ? lines.items[lines.count - 1] : "");
    unsigned mask = 0xFFu; double scale = 2.5e-1; int squared = SQUARE(7);
    return lines.count > 0 ? 0 : 1;
}
```

## C++

```cpp
#include <algorithm>
#include <iostream>
#include <memory>
#include <optional>
#include <string_view>
#include <vector>

namespace geometry {

/// A shape with an area.
class Shape {
public:
    virtual ~Shape() = default;
    [[nodiscard]] virtual double area() const noexcept = 0;
};

template <typename T>
concept Numeric = std::is_arithmetic_v<T>;

class Circle final : public Shape {
public:
    explicit Circle(double radius) : radius_{radius} {}
    double area() const noexcept override { return 3.14159265358979 * radius_ * radius_; }
private:
    double radius_;
};

template <Numeric T>
std::optional<T> largest(const std::vector<T>& values) {
    if (values.empty()) return std::nullopt;
    return *std::max_element(values.begin(), values.end());
}

} // namespace geometry

int main() {
    using namespace std::literals;
    std::vector<std::unique_ptr<geometry::Shape>> shapes;
    shapes.push_back(std::make_unique<geometry::Circle>(2.0));
    auto total = 0.0;
    for (const auto& shape : shapes) total += shape->area();
    constexpr auto label = "total area"sv;
    std::cout << label << ": " << total << '\n';
    if (auto max = geometry::largest(std::vector{3, 9, 4}); max.has_value()) {
        std::cout << "largest: " << *max << std::endl;
    }
    return shapes.empty() ? 1 : 0x0;
}
```

## C#

```csharp
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Shop.Orders;

/// <summary>Calculates order totals with discounts.</summary>
public sealed record Order(int Id, IReadOnlyList<LineItem> Items, string? Coupon = null);

public readonly record struct LineItem(string Sku, decimal Price, int Quantity);

[Serializable]
public class OrderService<TRepository> where TRepository : IRepository<Order>, new()
{
    private const decimal TaxRate = 0.0825m;
    private readonly TRepository _repository = new();

    public event EventHandler<decimal>? TotalCalculated;

    public async Task<decimal> TotalAsync(int orderId, bool includeTax = true)
    {
        var order = await _repository.FindAsync(orderId)
            ?? throw new InvalidOperationException($"Order {orderId} not found");

        decimal subtotal = order.Items.Sum(item => item.Price * item.Quantity);
        decimal discount = order.Coupon switch
        {
            "SAVE10" => subtotal * 0.10m,
            { Length: > 0 } code when code.StartsWith("VIP") => 25m,
            _ => 0m,
        };

        var total = Math.Max(0, subtotal - discount) * (includeTax ? 1 + TaxRate : 1);
        TotalCalculated?.Invoke(this, total); // Notify listeners.
        return Math.Round(total, 2, MidpointRounding.AwayFromZero);
    }
}

var verbatim = @"C:\orders\export.csv"; var hex = 0xFF; object? nothing = null;
```

## Java

```java
package com.example.inventory;

import java.time.Instant;
import java.util.*;
import java.util.stream.Collectors;

/**
 * Tracks stock levels and reports items that need reordering.
 */
public final class Inventory implements Iterable<Inventory.Item> {

    public record Item(String sku, int quantity, double price) {}

    private static final int REORDER_LEVEL = 10;
    private final Map<String, Item> items = new HashMap<>();

    @Override
    public Iterator<Item> iterator() {
        return Collections.unmodifiableCollection(items.values()).iterator();
    }

    public synchronized void adjust(String sku, int delta) throws IllegalArgumentException {
        Item current = items.getOrDefault(sku, new Item(sku, 0, 0.0));
        int next = current.quantity() + delta;
        if (next < 0) {
            throw new IllegalArgumentException("Stock for \"" + sku + "\" can't go below zero");
        }
        items.put(sku, new Item(sku, next, current.price()));
    }

    /** Items at or below the reorder level, cheapest first. */
    public List<Item> toReorder() {
        return items.values().stream()
                .filter(item -> item.quantity() <= REORDER_LEVEL)
                .sorted(Comparator.comparingDouble(Item::price))
                .collect(Collectors.toList());
    }

    public static void main(String[] args) {
        var inventory = new Inventory();
        inventory.adjust("A-100", 25);
        inventory.adjust("A-100", -18);
        System.out.printf("At %s: %d to reorder%n", Instant.now(), inventory.toReorder().size());
        long big = 1_000_000L; float ratio = 0.5f; boolean ok = true; Object none = null;
    }
}
```

## Kotlin

```kotlin
package app.weather

import kotlinx.coroutines.*
import kotlin.math.roundToInt

/** A forecast for one day. */
data class Forecast(val day: String, val highC: Double, val lowC: Double, val rainChance: Int = 0)

sealed interface Result<out T> {
    data class Ok<T>(val value: T) : Result<T>
    data class Failed(val reason: String) : Result<Nothing>
}

class WeatherRepository(private val api: WeatherApi, private val units: Units = Units.Metric) {

    suspend fun week(city: String): Result<List<Forecast>> = withContext(Dispatchers.IO) {
        try {
            val days = api.fetch(city, days = 7)
                .filter { it.rainChance in 0..100 }
                .sortedBy(Forecast::day)
            if (days.isEmpty()) Result.Failed("no data for $city") else Result.Ok(days)
        } catch (e: java.io.IOException) {
            Result.Failed("network: ${e.message ?: "unknown"}")
        }
    }

    fun describe(forecast: Forecast): String = when {
        forecast.rainChance > 70 -> "Rain likely"
        forecast.highC >= 30.0 -> "Hot, ${forecast.highC.roundToInt()}°"
        else -> "Fine"
    }

    companion object {
        const val MAX_DAYS = 14
        val hex = 0xFF_EC_DE_5E; val nothing: String? = null
    }
}
```

## Ruby

```ruby
# frozen_string_literal: true

require 'json'
require 'net/http'

module Billing
  # Generates invoices for a customer's unpaid orders.
  class InvoiceGenerator
    TAX_RATE = 0.2
    attr_reader :customer, :errors

    def initialize(customer, currency: :usd)
      @customer = customer
      @currency = currency
      @errors = []
    end

    def call
      orders = customer.orders.select { |o| !o.paid? && o.total.positive? }
      return nil if orders.empty?

      total = orders.sum(&:total) * (1 + TAX_RATE)
      {
        number: "INV-#{Time.now.strftime('%Y%m%d')}-#{customer.id}",
        lines: orders.map { |o| { id: o.id, amount: o.total.round(2) } },
        total: total.round(2),
        currency: @currency.to_s.upcase
      }
    rescue StandardError => e
      @errors << e.message
      false
    ensure
      log("invoice for #{customer.name}: #{@errors.empty? ? 'ok' : 'failed'}")
    end

    private

    def log(message) = warn("[billing] #{message}")
  end
end

puts Billing::InvoiceGenerator.new(customer).call.to_json if __FILE__ == $PROGRAM_NAME
hex = 0x1F; pattern = /\A\d{3}-\d{4}\z/; nothing = nil
```

## YAML

```yaml
# CI pipeline for a Swift package.
name: Build
on:
  push:
    branches: [main]
    tags: ["v*"]
  pull_request:

env:
  DEVELOPER_DIR: /Applications/Xcode_26.3.app/Contents/Developer
  RETRIES: 3
  RATIO: 0.75
  VERBOSE: false

jobs:
  test:
    runs-on: macos-15
    timeout-minutes: 30
    strategy:
      matrix:
        configuration: [debug, release]
    steps:
      - uses: actions/checkout@v7
      - name: Test (${{ matrix.configuration }})
        run: |
          swift test -c ${{ matrix.configuration }}
          echo "done"
      - name: Upload
        if: ${{ startsWith(github.ref, 'refs/tags/v') }}
        with:
          path: build/Cera.zip
          retention: ~
anchors:
  defaults: &defaults
    retries: 2
  job:
    <<: *defaults
    name: 'single quoted'
```

## TOML

```toml
# Configuration for the sample service.
title = "Cera sample"
version = "2.1.0"
debug = false

[server]
host = "0.0.0.0"
port = 8_080
timeout = 30.5        # seconds
started = 2026-10-17T09:30:00Z

[database]
url = 'postgres://localhost/cera'
pool = { min = 2, max = 16 }
replicas = ["db-1.internal", "db-2.internal"]

[[workers]]
name = "indexer"
threads = 4
schedule = """
Every hour,
on the hour."""

[[workers]]
name = "mailer"
threads = 1
enabled = true
ratio = 1e-3
mask = 0xDEAD_BEEF
```

## HTML

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Sign up &mdash; Cera</title>
  <link rel="stylesheet" href="/styles/main.css">
  <!-- Analytics are off until the user agrees. -->
</head>
<body class="page signup">
  <header id="top">
    <a href="/" aria-label="Home"><img src="logo.svg" alt="Cera" width="32" height="32"></a>
  </header>
  <main>
    <h1>Create your account</h1>
    <form action="/signup" method="post" novalidate>
      <label for="email">Email</label>
      <input id="email" name="email" type="email" required placeholder="you@example.com">
      <label><input type="checkbox" name="news" checked> Send me updates</label>
      <button type="submit" disabled>Sign up</button>
    </form>
  </main>
  <script type="module" src="/app.js" defer></script>
</body>
</html>
```

## CSS

```css
@import url("fonts.css");

/* Design tokens. */
:root {
  --accent: #4a89dc;
  --radius: 6px;
  --gap: clamp(0.5rem, 2vw, 1.5rem);
}

@media (prefers-color-scheme: dark) {
  :root { --accent: hsl(214 68% 64%); }
}

.card > .title::before,
.card:hover .title {
  content: "→ ";
  color: var(--accent);
  font: 600 1.125rem/1.4 "Helvetica Neue", system-ui, sans-serif;
}

.grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
  gap: var(--gap);
  transition: transform 150ms ease-in-out, opacity 0.2s !important;
}

#signup input[type="email"]:focus-visible {
  outline: 2px solid rgba(74, 137, 220, 0.6);
  border-radius: calc(var(--radius) - 2px);
}

@keyframes fade-in {
  from { opacity: 0; transform: translateY(4px); }
  to   { opacity: 1; transform: none; }
}
```

## SQL

```sql
-- Monthly revenue per customer, with their rank, for active customers only.
WITH monthly AS (
    SELECT
        c.id AS customer_id,
        c.name,
        DATE_TRUNC('month', o.created_at) AS month,
        SUM(oi.quantity * oi.unit_price) AS revenue,
        COUNT(DISTINCT o.id) AS orders
    FROM customers AS c
    INNER JOIN orders AS o ON o.customer_id = c.id
    LEFT JOIN order_items AS oi ON oi.order_id = o.id
    WHERE c.status = 'active'
      AND o.created_at >= NOW() - INTERVAL '12 months'
      AND oi.unit_price > 0.0
    GROUP BY c.id, c.name, DATE_TRUNC('month', o.created_at)
    HAVING SUM(oi.quantity) > 10
)
SELECT
    customer_id,
    name,
    month,
    revenue,
    RANK() OVER (PARTITION BY month ORDER BY revenue DESC) AS rank,
    CASE WHEN revenue >= 10000 THEN 'gold' WHEN revenue >= 1000 THEN 'silver' ELSE NULL END AS tier
FROM monthly
ORDER BY month DESC, rank ASC
LIMIT 100;

/* Keep the totals current. */
CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders (customer_id, created_at);
UPDATE customers SET status = 'dormant', updated_at = CURRENT_TIMESTAMP WHERE last_order_at < '2025-01-01' AND is_vip = FALSE;
```

## Markdown

```markdown
# Release notes

Cera **0.5** adds *diagrams* and a ~~beta~~ finished outline. See [the changelog](CHANGELOG.md) or <https://example.com>.

## What's new

- [x] Mermaid diagrams, drawn natively
- [ ] Syntax highlighting with `tree-sitter`
  1. Phase one
  2. Phase two

> **Note:** large files still open in about a second.

| Feature | Status |
|:--------|-------:|
| Outline | done   |

![screenshot|500](images/outline.png)

---
```

## Diff

```diff
diff --git a/Sources/Cera/CodeEditing.swift b/Sources/Cera/CodeEditing.swift
index 3f2a1b0..8c9d4e7 100644
--- a/Sources/Cera/CodeEditing.swift
+++ b/Sources/Cera/CodeEditing.swift
@@ -42,9 +42,10 @@ struct FencedCodeBlock: Equatable {
     func indentUnit(in text: NSString) -> String {
         var smallest = Int.max
         for line in body {
             let code = codePart(of: text.substring(with: line))
             if code.hasPrefix("\t") { return "\t" }
             let spaces = code.prefix { $0 == " " }.count
-            if spaces > 0, spaces < code.count { smallest = min(smallest, spaces) }
+            // A single space is alignment, not indentation.
+            if spaces > 1, spaces < code.count { smallest = min(smallest, spaces) }
         }
```
