# DataRaft

**DataRaft** is a minimalistic Swift library for safe and controlled SQLite access in multithreaded environments.

## Overview

**DataRaft** is a high-level infrastructure library that simplifies safe SQLite usage in Swift. It provides thread-safe database access, transaction handling, and a migration system—without hiding SQL or enforcing an ORM.

The library is built on top of [DataLiteCore](https://github.com/angd-dev/data-lite-core) (a Swift wrapper around SQLite) and [DataLiteCoder](https://github.com/angd-dev/data-lite-coder) (for encoding and decoding values), and is designed for real-world projects where control, reliability, and predictability matter.

**The goal of DataRaft** is to give developers full control over SQL while offering a simple and safe interface for day-to-day database work.
