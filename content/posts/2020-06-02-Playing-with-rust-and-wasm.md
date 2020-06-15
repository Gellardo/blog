---
title: "Playing With Rust and Wasm"
date: 2020-06-02T21:52:04+02:00
draft: true
---

I have read a lot about how Wasm is great for porting non-JS languages into the browser and maybe even into a general Lambda runtime.
Also better security and ability to compile libraries into Wasm and use them in other languages.
So I wanted to try it and document my experience using Rust+Wasm to build a game of life using wasm (before knowing about the book).

**TLDR:** If you want to learn a lot more than fits into a post, read the [official rust+wasm introduction][wasm-life-introduction] instead of reading about me stumbling around.

## Wasm? Rust?
- wasm is like assembler for the browser
- stronger security guarantees built into the language
- currently mostly browser, there are projects working to provide a runtime for bare-metal (kinda jvm/graal? like)
- rust is a systems programming language with focus on safety and performance
- also has very nice tooling for wasm

## Bootstraping a Rust Game of Life implementation
Quick recap:
Conway's Game of Life is a game/simulation of a universe of cells that live or die depending on their neighbors.
Each tick, if the cell was previously alive, it will stay alive if 2-3 of its neighbors were alive.
If it was dead, it needs exactly 3 of it's neighbors to be alive.
Otherwise the cell will be dead.

These simple rules can produce complex behaviour like this "glider gun" ([source](https://commons.wikimedia.org/wiki/File:Gospers_glider_gun.gif)):
![glider gun](https://upload.wikimedia.org/wikipedia/commons/e/e5/Gospers_glider_gun.gif)

### Implement simulation logic
To bootstap a crate for the game logic to reside in, I used one of the provided templates.
Using `npm init rust-webpack` ([source](https://github.com/rustwasm/rust-webpack-template)), I have a starting point without having to fiddle with npm, webpack or cargo.
Later I will go into more detail of what that template includes.

A datastructure is needed to hold the state of the universe.
I'm using a 2-dimensional array and store the current and last state, switching between them to avoid allocations.
The `#[wasm_bindgen]` annotation exposes the struct in the wasm module.
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

As a sidenote, it is really nice that rust handles the glue code for moving data types across the JS-Wasm border.
Otherwise, the only option for sharing is to write your own serializer/deserializer to the shared memory.
The Wasm API only has basic valuetypes, so you end up converting to bytes and back on both sides.
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
Lastly, the template provids a function with `#[wasm_bindgen(start)]` that is run once the module is imported.
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
- webpack -> wasm-pack-plugin -> runs wasm-pack -> runs wasm-bindgen
- interaction via C ABI: can do "C" external calls for js functions and lib type is cdyn
- `web_sys` for browser bindings like console (`println!` does not work)
- crate `console_error_panic_hook` for having panics print a trace to the console (could be added only for dev)
- `wasm-bindgen-test` to run tests in headless browsers (not used yet)

### What I understood of what happens under the covers of wasm-pack
Generated files:
- `index_bg.d.wasm`: the compiled wasm binary
- `index_bg.d.ts`: seems to be a "header" file of generated rust functions, not usable though (e.g. no body, using numbers (= pointers) as parameters)
- `index_bg.js`: looks like the actual js implementation, nicely wrapping the the wasm heap pointer magic
- `index.d.ts`: looks like typescript headers for things in `index_bg.js`
- `index.js`: just imports the wasm file and `index_bg.js`, (optionally) calls the wasm `main_js` entrypoint


## Bring the game to life in the browser
The rust crate already simulates the game in the console.
But nobody looks there, so let's add some nicer visuals.
### Handing Strings from Wasm to JS
The easiest way to do that is to just move the printing from the console output to a text element of the site.
So I write a minimal amount of JS, that takes the output of `game.prettier_state())` and sets the `textContent` of a `<pre>` element.
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
2. Why does that function have the wasm module as a parameter?

Before answering the second observation, I need to say that I have very little experience with JS so I might have solved this the complicated way.
By default, the template contains the expression `import("../pkg/index.js")` to include the Wasm module.
This is an asynchronous import of that module (notice the parentheses) and it does not make the module available immeidately like an usual import.
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
- I could set the text content, but getting there relied on finding the right stackoverflow question
- Kinda like JS: Get `window` (rust only) -> `document` -> `element_by_id`
  (sideeffect: import of the `web-sys` crate needed a bunch more feature flags)
- IDE says: use `sleep()` to sleep, browser/wasm says: whats that? time? nope
- tried to call js `setTimeout` but failed constructing a fitting callback
- I tried and failed, could not find nice documentation (once I reached `setTimeout`)
  Possible sidetrack: Wasm modules, why it does not work, (how to fix it?)
- `Gloo` and its posts might allow me to so now

## It's really performant, right?
- well no, same code is far faster in js
- copy-pasted rust code and do minor changes to make it valid JS
  (Find that rust fixed a bug in my code, not exchanging struct-fields)
- on pageload run tick 1000 times and measure the time
- `mem::swap` sometimes works and then goes back to not working
- not multithreaded/parallel, running the benchmark stops the visual simulation

## What's next
- Try again to get rid of js glue code (PURE Rust!!).
  Came across Gloo(?) blog post that has exactly the problematic code, so I want to have a 2nd try
- Explore using `wasm-bindgen-test` for headless browser tests from Rust
- Performance optimizations? Wasm is supposed to be faster!

## Links
[wasm-life-introduction]: https://rustwasm.github.io/docs/book/introduction.html
[wasm-bindgen-docs]: https://rustwasm.github.io/docs/wasm-bindgen/
[wasm-pack-docs]: https://rustwasm.github.io/docs/wasm-pack/
