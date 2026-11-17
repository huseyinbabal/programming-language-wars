# Programming Language Wars

The same program in different languages, on the same machine, measured. Each folder is one comparison, with the code and the scripts that produced its numbers.

| Folder | Comparison |
| --- | --- |
| [`go-vs-rust/`](go-vs-rust/) | Go vs Rust: the same in-memory LRU cache under the same k6 load, both on their own CPU cores, live Grafana dashboards |
| [`rust-vs-cpp/`](rust-vs-cpp/) | Rust vs C++: the same four programs (sort, word count, integer-key hash maps, parallel word count) with the same LLVM version on one 16-core server: code, raw results, profiles |
