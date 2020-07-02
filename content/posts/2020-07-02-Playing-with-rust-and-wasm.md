---
title: "Playing With Rust and Wasm"
date: 2020-07-02T21:52:04+02:00
tags: [rust,wasm]
draft: true
---

I have read a lot about how Wasm is great for porting non-JS languages into the browser and maybe even into a general Lambda runtime.
Also better security and ability to compile libraries into Wasm and use them in other languages.
So I wanted to try it and document my experience using Rust+Wasm to build a game of life using Wasm (before knowing about the book).

**TLDR:** If you want to learn a lot more than fits into a post, read the [official rust+wasm introduction][wasm-life-introduction] instead of reading about me stumbling around.

## Wasm? Rust?
Let's start with my technology choices:

> WebAssembly (abbreviated Wasm) is a binary instruction format for a stack-based virtual machine.
> [Wasm homepage](https://webassembly.org/)

So Wasm started out to be like binary assembly for the browser, allowing e.g. languages other than JS to be compiled to Wasm and run in the browser.
Wasm also has built-in safety guarantees like memory-safety and sandboxed execution.
It also has a strong integration with the JS VM in the browser, allowing calls from and to regular JS.
It is designed with modularity in mind, providing platform specific functionality (time, JS access, file access, ...) through modules only.
Also there are non-web platforms like node.js and [wasi](https://wasi.dev/) that allow using Wasm outside of the browser.

Wasm's main selling point is speeding up compute-heavy tasks in the browser and using it to allow running any code safely almost anywhere.

[Rust](https://www.rust-lang.org/) is a systems programming language with a focus on safety and performance.
It's unique borrow-checker/data ownership rules also prevent data races and promise thread-safety at compile time.
The Rust community is also pretty active in the Wasm space, resulting in some nice tooling that I can just pick up and use.

Enough with the introductions, let's get started.

## Bootstrapping a Rust Game of Life implementation
Quick recap:
Conway's Game of Life is a game/simulation of a universe of cells that live or die depending on their neighbors.
Each tick, if the cell was previously alive, it will stay alive if 2-3 of its neighbors were alive.
If it was dead, it needs exactly 3 of it's neighbors to be alive.
Otherwise the cell will be dead.

These simple rules can produce complex behavior like this "glider gun" ([source](https://commons.wikimedia.org/wiki/File:Gospers_glider_gun.gif)):
![glider gun](https://upload.wikimedia.org/wikipedia/commons/e/e5/Gospers_glider_gun.gif)

### Implementing the simulation
Rust organizes code into creates which might contain further modules.
To bootstrap a crate for the game logic to reside in, I used one of the official templates.
Using `npm init Rust-webpack` ([source](https://github.com/rustwasm/rust-webpack-template)), I have a starting point without having to fiddle with npm, webpack or cargo.
Later I will go into more detail of what that template includes.

A data structure is needed to hold the state of the universe.
I'm using a 2-dimensional array and store the current and last state, switching between them to avoid allocations.
The `#[wasm_bindgen]` annotation exposes the struct in the Wasm module.
The build fails if an exposed function or type would expose an unexposed type as a field/in the signature.
```rust
const SIZE: usize = 16;
type Universe = [[u8; SIZE]; SIZE];

#[wasm_bindgen]
#[derive(Debug)]
pub struct GameOfLife {
    state: Universe,
    last: Universe,
}
```

Now I can implement a single tick of the universe by moving exchanging current and last state, overwriting the previous state.
Since the universe has a limited size, I have to choose how to handle the borders:
Either treat cells outside the border as dead or wrap around to the other side, basically creating a torus.
I liked the idea of an endless glider, so I implemented the wrapping.
```rust
#[wasm_bindgen]
impl GameOfLife {
    pub fn tick(&mut self) {
        let tmp = self.last;
        self.last = self.state;
        self.state = tmp;

        for x in 0..self.last.len() {
            for y in 0..self.last[x].len() {
                self.state[x][y] = Self::will_be_alive(self.last, x, y)
            }
        }
    }

    fn will_be_alive(state: Universe, x: usize, y: usize) -> u8 {
        let mut alive_neighbors = 0;

        // Rust makes sure that usize can't get negative.
        // So using addition and modulo is simpler than a bunch of casting.
        for i in SIZE - 1..=SIZE + 1 {
            for j in SIZE - 1..=SIZE + 1 {
                if i == SIZE && j == SIZE { // don' count self
                    continue;
                }
                // turns into a wrapping universe
                let x_i = (x + i) % SIZE;
                let y_j = (y + j) % SIZE;
                alive_neighbors += state[x_i][y_j];
            }
        }

        return match (state[x][y], alive_neighbors) {
            (0, 3) | (1, 2) | (1, 3) => 1,
            _ => 0,
        };
    }
}
```

Add a method to translate the `Universe` into a `String` for easy pretty printing in JS.
```rust
#[wasm_bindgen]
impl GameOfLife {
    pub fn prettier_state(&self) -> String {
        let mut s = String::new();
        for line in &self.state {
            for cell in line {
                s += match cell {
                    1 => "█",
                    _ => "░",
                }
            }
            s += "\n"
        }
        s
    }
}
```

As a side note, it is really nice that Rust handles the glue code for moving data types across the JS-Wasm border.
Otherwise, the only option for sharing is to write your own serializer/deserializer to the shared memory.
The Wasm API only has basic value types, so you end up converting to bytes and back on both sides.
(And handling pointers into the Wasm memory).

And generate the glider in the universe.
```rust
#[wasm_bindgen]
pub fn game() -> GameOfLife {
    let mut game = gameoflife::GameOfLife::new();
    game.set_alive(1, 2);
    game.set_alive(2, 3);
    game.set_alive(3, 1);
    game.set_alive(3, 2);
    game.set_alive(3, 3);
    game
}
```

Notice that all those functions are annotated with `#[wasm_bindgen]` so that they can be called from JS later on.
Lastly, the template provides a function with `#[wasm_bindgen(start)]` that is run once the module is imported.
In there, the game can be set up and the state is printed after each tick to `console.log()`
```rust
#[wasm_bindgen(start)]
pub fn main_js() -> Result<(), JsValue> {
    let mut game = game();
		for i in 0..100 {
		    game.tick();
				console::log_1(&JsValue::from_str(&game.prettier_state()));
		}

    Ok(())
}
```

### Looking into the template
Since the simulation works, let's move on to my (shallow) understanding of what is happening behind the scenes of the template.

The most important part is the inclusion of a webpack plugin for [`wasm-pack`](https://github.com/rustwasm/wasm-pack).
The plugin automatically (re-)generates the Wasm module and the JS glue code (with TypeScript type information) to use it comfortably.
Multiple files are created for this purpose:
- `index_bg.d.wasm`: the Wasm module created from the crate
- `index_bg.js`: JS glue code to allow access to WASM functions and values without having to resort to the low level API and memory access for information exchange.
- `index.js`: Combines the other files into a single import and runs static setup functions (e.g. functions with `#[wasm_bindgen(start)]`).
   The template included a single line `index.js` which performs the import for the served web page.

Since wasm-pack handles all of the compilation, what else is there?
The Rust crate is using the library type `cdyn` (C dynamic library) which hints that interactions use the C ABI (or at least some step of the compilation pipeline).

Wasm is highly modular, and appropriately there are a number crates that provide necessary and/or nice-to-have bindings for the web platform.
`web_sys` is an auto-generated crate that translates all browser JS functions to Rust functions.
This includes e.g. accessing elements in the DOM or using the browser console for printing.
(There is no `stdout` in the browser, so `println!` is not possible).
That is also the crate `js_sys` for pure JS bindings.

The crate `console_error_panic_hook` improves the development process by changing the output for runtime panics.
By default the console output is rather cryptic.
The crate adds enough context information about the stack trace, source file and line numbers to make debugging panics much easier.
And with some feature flag magic, it can only be included in dev to reduce the Wasm file size of the production build.

I haven't really used the last crate, but the initial tests looked interesting:
`wasm-bindgen-test` allows to specify tests that run in a headless browsers.
This is quite helpful for writing end-to-end tests of the Wasm functionality but I did not have the time to play with it.
*Yet*.

## Bring the game to life in the browser
The Rust crate already simulates the game in the console.
But nobody looks there, so let's add some nicer visuals.
### Handing Strings from Wasm to JS
The easiest way to do that is to just move the printing from the console output to a text element of the site.
So I write a minimal amount of JS, that takes the output of `game.prettier_state()` and sets the `textContent` of a `<pre>` element.
Wrap that in a closure and recursively call `requestAnimationFrame(closure)` to run the simulation at a stable 60 FPS.
We made a poor man's canvas!

```javascript
function game(wasm) {
    const gameElement = document.getElementById("game")
    const g = wasm.game()
    const renderloop = async () => {
        gameElement.textContent = g.prettier_state()
        g.tick()
        await new Promise(r => setTimeout(r, 100));
        requestAnimationFrame(renderloop)
    }
    requestAnimationFrame(renderloop)
}
```

Now I just skipped a minor and a major thing:
1. 60 FPS (the goal of `requestAnimationFrame`) was to fast for my liking so I added a 100 ms sleep.
2. Why does that function have the Wasm module as a parameter?

Before answering the second observation, I need to say that I have very little experience with JS so I might have solved this the complicated way.
By default, the template contains the expression `import("../pkg/index.js")` to include the Wasm module.
This is an asynchronous import of that module (notice the parentheses) and it does not make the module available immediately like an usual import.
My first try was to change that to a normal import statement, but that did not work:
> WebAssembly module is included in initial chunk.
> This is not allowed, because WebAssembly download and compilation must happen asynchronous.
> Add an async splitpoint (i. e. import()) somewhere between your entrypoint and the WebAssembly module

Hmm, alright it seems that the `import()` is needed after all.
So I took the way of least resistance and future spaghetti code and added a callback to the `import()` statement, which calls the function with the imported module.

```javascript
import( "../pkg/index.js" ).then(wasm => game(wasm)).catch(console.error);
```

Some more googling suggests, that this might be a [limitation of webpack](https://github.com/webpack/webpack/issues/6615)).
But it works like this and as long as I don't need to extend it, that's fine.

### Can I get rid of manual JS completely?
Most of the logic is written in Rust, but there is still some JS glue needed.
So I tried to change that.

First, I looked into setting `textContent` from Rust.
There is a `Document` type in the `web-sys` crate, but the [documentation](https://docs.rs/web-sys/0.3.39/i686-unknown-linux-gnu/web_sys/struct.Document.html) only tells me that it can create a new `Document`.
As well as about 4000 other things, since it is auto-generated and has every, EVERY function the browser provides for the document.
But I want the already existing `Document`, the same that JS provides by default.

Off to see if anybody else had that problem and luckily, [someone did](https://stackoverflow.com/questions/61635487/rust-wasm-how-to-access-htmldocument-from-web-sys):
By going through `Window` to `Document`, I could finally use `element_by_id` to get the correct element and set its content.
One interesting side note: pretty much every feature of `web-sys` is behind a feature-flag to reduce the footprint of the dependency, unless you actually need certain functionality.
And the docs just tell you which ones you need. Neat.

Now only run `tick()` and `setText` in an endless loop and it works.
Or not: The text content was not updated and the page was not responding.
So, perhaps add some `sleep()` calls in the loop to yield control back to the browser?
Well, since is strictly sandboxed, there is no access to a time source without a module provided by the runtime.

Last, I tried to rewrite the same `requestAnimationFrame` code with `setTimeout` as in JS.
But that did not go well, since I lacked any understanding if/how to hand in functions from JS or use Rust closures to be called by `requestAnimationFrame`.
Having spent about 3-4 hours trying to figure out a solution, I decided to cut my losses and accept a minimal amount of JS.

## It's really performant, right?
Time to get a look at the performance of this solution.
So I copy&pasted the Rust code to JS and adjusted the syntax accordingly.
As the benchmark, I use the same starting state and run it for 1000 ticks with each implementation.

One thing to take into account is that the context switch between JS and Wasm might take some time.
So there are 2 categories, one calling `tick()` multiple times from JS and having one call to the iteration implemented in Rust.

Eagerly awaiting the first results:

| JS | Rust | Rust with only one context switch |
|---|---|---|
| 14ms | 1.7s | 1.6s |

Well, that's certainly not what I expected: 2 orders of magnitude slower!
Let's see what I can find out.

#### Too many allocations
One thing I did not talk about, that my original code had a bug, that Rust thankfully fixed for me.
Instead of exchanging the arrays holding last and the current state during tick, I only assigned the current to the last.
To go into the specifics why it still worked correctly, is besides the point.
Suffice to say Rust copied the array instead of moving it and therefore fixed my bug.

But it also means, that for each tick, the Rust code copies the array (of arrays) once.
Allocation is slow on normal architectures and it's the same here.
So lets fix that:

```patch
+  let tmp = self.last;
   self.last = self.state;
+  self.state = tmp;
```

Alternatively, I also tried using `mem::swap` to directly swap the pointers.
Both solutions did work, ... sometimes:

| | JS | Rust | Rust with only one context switch |
|---|---|---|---|
| Before | 14ms | 1.7s | 1.6s |
| Now (1) |  | 270ms | 250ms |
| Now (2) |  | 1.7s | 1.6s |

#### Huh?
I'm stumped at that point.
The code explicitly says, I want to swap the pointers, but the compiler ignores it.
And I could find no real pattern, when the "correct" interpretation was used.
Sometimes the 3-way swap worked, sometime the `mem::swap` did.
Once the behavior changed, it took a few compiles to change again.
Especially confusing was that I was only editing JS and HTML at the time it first occurred (trying to add a "run benchmark" button).
`¯\_(ツ)_/¯`

Even in the best case, the code still runs an order of magnitude slower than JS.
So I looked into the [official book][wasm-life-introduction] to see how their solution performed.
One screenshot in the time profiling section shows that their ticks (with a larger universe) take about `1ms`.
So improving my (best-case) code by another 2 orders of magnitude should be possible.
But this post is long enough, so I'll keep performance tuning for a future post.

Interesting side note:
I just assumed that, since I could create multiple game instances, that they could automatically be running in parallel.
But while the benchmarks run, the visualized simulation is stopped.
Even if I tried to import the module a second time using a separate `import()` statement.
On the other hand, JS also runs single-threaded in the Browser, unless you use webworkers.

## What's next
I will leave some topics open for future posts, because they either are not yet implemented or not researched enough.

1. Optimize the performance of my implementation.
   This involves learning about the necessary tools, performance measurement and debugging and sounds like an interesting challenge.
	 Wasm should be faster and I want to better understand why my implementation isn't.
1. I want to try getting rid of the JS glue code again, just out of spite.
   Reading a [blogpost by Gloo][gloo-post], a modular Wasm toolkit, I found solutions for all the unsolved problems I have encountered.
1. Explore using `wasm-bindgen-test` for headless browser tests from Rust

Thanks for reading!

## Links
- [An official book which introduces rust+wasm][wasm-life-introduction]
- [Docs for wasm-bindgen][wasm-bindgen-docs]
- [Docs for wasm-pack][wasm-pack-docs]
- [Blogpost by Gloo][gloo-post]

[wasm-life-introduction]: https://rustwasm.github.io/docs/book/introduction.html
[wasm-bindgen-docs]: https://rustwasm.github.io/docs/wasm-bindgen/
[wasm-pack-docs]: https://rustwasm.github.io/docs/wasm-pack/
[gloo-post]: https://rustwasm.github.io/2019/03/26/gloo-onion-layers.html
