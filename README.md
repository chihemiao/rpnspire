# rpnspire

![rpnspire logo](https://github.com/johannes-wolf/rpnspire/blob/main/doc/logo.png?raw=true)

<p align="center">
An RPN interface for the TI Nspire CX
</p>

As I really liked the rpn application for the TI-89 but could not find a usable RPN implementation for the TI nSpire, I've created rpnSpire, a powerful RPN implementation
with many features such as searchable menus, autocompletion, an application framework in lua, a matrix editor, and many more.

## VCE Maths toolkit (Methods + Specialist)

This fork adds a solver toolkit for the tech-active Exam 2 of VCE Mathematical Methods (MM) and Specialist Mathematics (SM) on the TI-Nspire CX II CAS. Every topic is marked MM or SM. It covers:

- function graphs with asymptotes, turning points, inflection points and non-differentiable points;
- unknown constants from conditions (`f(1)=3`, `f'(2)=0`, points, turning points, tangents, asymptotes);
- transformations y = A f(n(x + b)) + c in VCE order, with the mapping of points, or found from two rules;
- simultaneous linear equations with a parameter (unique, no or infinitely many solutions);
- areas, volumes of revolution, arc length and surface area for y = f(x), x = g(y) and parametric curves;
- DE models (growth, cooling, logistic, mixing, Euler, related rates), with graphs;
- SUVAT and variable-acceleration kinematics;
- probability in one place: normal, binomial, discrete and continuous (PDF) random variables, sample proportions (p̂) and their confidence intervals, sample means, linear combinations, and hypothesis tests with Type I/II errors.

You type in the known values and it shows exact results (enter or a click switches to decimals), 2D maths like the CAS screen, and VCE-style working. History and tags are kept with the document. The interface is designed for easy reading:

- few choices per screen;
- an example button in every empty problem;
- answers highlighted right under the inputs;
- soft colours and short hints.

It comes in two versions: the English-only `vce.tns` (`npm run build:vce`; no Chinese text and no language setting) and `vce_zh.tns` with Chinese (中英双语, `npm run build:vce-zh`; working steps stay in English). It is also inside `rpn.tns` (English) under <kbd>.</kbd><kbd>a</kbd> › *VCE Maths toolkit*. See [doc/vce.md](doc/vce.md).

## Install

Use the latest build from the *GitHub actions* and put it under `MyWidgets` on your nspire CX.

## Agent development workflow

This fork keeps the original rpnspire application structure. `AGENTS.md` gives coding agents the target runtime, source layout, and validation boundary.

On macOS or Linux, install Node.js, npm, Lua, a C compiler, `make`, and zlib development headers. Then run:

```sh
npm ci
npm test
npm run build
```

The build writes `bundle.lua` and `rpn.tns`; `npm run build:vce` writes `vce_bundle.lua` and `vce.tns`. It downloads and builds Luna v2.1 locally in `.luna/` on first use. To test a single Lua script without bundling the full application, run `npm run build:hello`; this converts `examples/hello.lua` to `hello.tns`.

The generated `.tns` needs to be opened in TI-Nspire CX CAS software or on a CX II CAS handheld for runtime validation. Compilation alone verifies the local toolchain.

## Usage

<p align="center">
<img src="https://github.com/johannes-wolf/rpnspire/blob/main/doc/rpn.gif" width="300px"></img>
</p>

The input field of rpnspire supports autocompletion for functions, variables and units. To trigger completion,
press <kbd>tab</kbd>. Completion uses characters left to the cursor as compeltions prefix. Typing `so<tab>` will
present you the first entry of a list of completion candidates starting with `so`. Pressing <kbd>tab</kbd> multiple times loops through all candidates. To accept a completion press hit <kbd>enter</kbd>. Completions are sorted by use (see [config/stats.lua](config/stats.lua)). Typing with the completion pop-up open, further filters the candidates.

### RPN-Mode

RPN-mode is the default mode of rpnspire. In RPN-mode, pressing an operator or function key submits the current input
and directly evaluates the operator or function pressed. If the cursor is not at the last position, input mode is set to non-rpn (alg) automatically.

<p align="center">
<img src="https://github.com/johannes-wolf/rpnspire/blob/main/doc/stack.gif" width="300px"></img>
</p>

Calling functions from RPN-mode is done by just entering the function name without parentheses.
To set the argument for variable argument functions, use parentheses.

<p align="center">
<img src="https://github.com/johannes-wolf/rpnspire/blob/main/doc/rpn-zeros.gif" width="300px"></img>
</p>

### Matrix Editor

RPNspire features a matrix editor to write and edit matrixes.

<p align="center">
<img src="https://github.com/johannes-wolf/rpnspire/blob/main/doc/matrix.gif" width="300px"></img>
</p>

## Settings

See [config/config.lua](config/config.lua), to adjust defaults.

## Bindings

See [config/bindings.lua](config/bindings.lua), to configure your own bindings.

rpnspire uses key-sequences for its bindings. <kbd>.</kbd><kbd>e</kbd> means: Press `.` and then press `e`.
The current sequence of keys pressed (that are part of a binding) is displayed by a dialog at the
top of the screen.

### Input
| Key                          | Function                                                |
|------------------------------|---------------------------------------------------------|
| <kbd>.</kbd><kbd>u</kbd>     | Undo                                                    |
| <kbd>.</kbd><kbd>r</kbd>     | Redo                                                    |
| <kbd>left</kbd>              | Move cursor left; if empty: roll up                     |
| <kbd>right</kbd>             | Move cursor right; if empty: roll down                  |
| <kbd>up</kbd>                | Focus stack                                             |
| <kbd>down</kbd>              | Swap stack 1 & 2                                        |
| <kbd>enter</kbd>             | Submit input; if empty: dup 1                           |
| <kbd>tab</kbd>               | Start completion for current input                      |
| <kbd>.</kbd><kbd>left</kbd>  | Roll up beginning                                       |
| <kbd>.</kbd><kbd>right</kbd> | Roll down end                                           |

| Key                          | Function                                                |
|------------------------------|---------------------------------------------------------|
| <kbd>.</kbd><kbd>=</kbd>     | Store Y in X                                            |
| <kbd>.</kbd><kbd>+-*/^</kbd> | Push dot operator                                       |
| <kbd>.</kbd><kbd>s</kbd>     | Store interactive                                       |
| <kbd>.</kbd><kbd>x</kbd>     | Solve interactive                                       |
| <kbd>.</kbd><kbd>e</kbd>     | Edit last expression                                    |
| <kbd>.</kbd><kbd>l</kbd>     | Push list                                               |
| <kbd>.</kbd><kbd>,</kbd>     | Join X and Y as Vector or List (depending on type of Y) |
| <kbd>.</kbd><kbd>/</kbd>     | Explode interactive                                     |
|------------------------------|---------------------------------------------------------|
| <kbd>.</kbd><kbd>v</kbd>     | Display variables                                       |
| <kbd>.</kbd><kbd>a</kbd>     | Display apps/tool                                       |
| <kbd>.</kbd><kbd>b</kbd>     | Display bindings                                        |
| <kbd>.</kbd><kbd>m</kbd>     | Open matrix editor                                      |
| <kbd>.</kbd><kbd>return</kbd> | Show command palette editor                            |


### Stack
| Key                              | Function                                                        |
|----------------------------------|-----------------------------------------------------------------|
| <kbd>left</kbd>                  | Roll stack up (1)                                               |
| <kbd>right</kbd>                 | Roll stack down (1)                                             |
| <kbd>up</kbd>                    | Move selection up                                               |
| <kbd>down</kbd>                  | Move selection down, focus input if out of bounds               |
| <kbd>backspace</kbd>             | Delete selected item                                            |
| <kbd>enter</kbd>                 | Duplicate selected item                                         |
| <kbd>c</kbd>                     | Copy selected expression to input                               |
| <kbd>r</kbd>                     | Copy selected result to input                                   |
| <kbd>7</kbd>                     | Select bottom (oldest)                                          |
| <kbd>3</kbd>                     | Select top (newest)                                             |
| <kbd>tab</kbd>/<kbd>escape</kbd> | Focus input                                                     |

### Matrix
#### Grid
| Key                          | Function            |
|------------------------------|---------------------|
| <kbd>.</kbd><kbd>left</kbd>  | Move to column 1    |
| <kbd>.</kbd><kbd>right</kbd> | Move to last column |
| <kbd>.</kbd><kbd>up</kbd>    | Move to first row   |
| <kbd>.</kbd><kbd>down</kbd>  | Move to last row    |
| <kbd>=</kbd>                 | Evaluate cell       |
| <kbd>ctx</kbd>               | Show context menu   |

#### Edit
| Key              | Function                             |
|------------------|--------------------------------------|
| <kbd>,</kbd>     | Submit input and move to next column |
| <kbd>enter</kbd> | Submit input and move to next row    |

## Features
* [x] RPN interface supporting (nearly) all of the nspires operators
* [x] Stack manipulation functions (See global keybindings)
* [x] Undo and redo (<kbd>.</kbd><kbd>u/r</kbd>)
* [x] Autocompletion for functions, variables and units
* [x] Nested keyboard shortcuts

## What is not working
* It is not possible to call TI-Basic Apps from Lua
