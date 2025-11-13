# RaRailJump (轨道跃迁站)

English | [简体中文](#-简体中文-版本)

_A teleporter mod that allows trains and engineers to instantly travel between two distant, paired portals._

[Factorio Mod Portal Link](https://mods.factorio.com/mod/zzzzz) | [GitHub Repository](https://github.com/VariousTrick/railjump)

---

## Table of Contents

*   [About the Mod](#about-the-mod)
*   [Core Features](#core-features)
*   [Getting Started](#getting-started)
*   [Resources & Consumption](#resources--consumption)
*   [Compatibility](#compatibility)
*   [Acknowledgements](#acknowledgements)
*   [Future Plans](#future-plans)

---

## About the Mod

**RailJump** brings an endgame logistics revolution to your factory. The design of this mod is entirely inspired by Earendel's Space Exploration and aims to bring the magnificent concept of the "Space Elevator" to all Factorio engineers in a standalone package, compatible with both vanilla and other large mods.

You will be able to construct massive portals, pair them, and establish an instantaneous train transportation network across the entire planet, or even between different planets.

**Important Disclaimer**: The development of this mod was entirely assisted by an AI. The developer himself primarily acts as the "director" and "tester" of the project. This is an experimental project exploring the possibilities of AI-assisted development. If you have any suggestions regarding the mod's design or balance, your feedback is always welcome, and we will continue to iterate and improve it with the AI.

## Core Features

*   **Instant Train Teleportation**: Instantly teleports an entire train (including its cargo, fluids, equipment, and passengers) from one portal to its paired counterpart.
*   **Player Teleportation**: Engineers can also use the portals for rapid personal travel.
*   **Cross-Surface Power Grid**: Paired and connected portals can share the same power network, allowing you to transmit power from your main base to remote outposts without any loss.
*   **Two Game Modes**:
    *   **Consumption Mode (Default)**: Teleporting and maintaining the power grid require dedicated late-game resources, bringing new logistical challenges.
    *   **Cost-Free Mode**: For players who prefer a "sandbox" or "creative" experience, all costs can be disabled for unrestricted building and planning.
*   **Configurable**: The in-game mod settings menu allows you to adjust the power grid maintenance cost and toggle related warning messages in real-time.

## Getting Started

1.  **Research Technology**: (This part is planned for the future; all recipes are currently available from the start).
2.  **Craft Core Materials**:
    *   **[item=chuansongmen-exotic-matter] Exotic Matter**: The core fuel for teleportation, produced in a **Centrifuge** via a complex endgame recipe.
    *   **[item=chuansongmen-personal-stabilizer] Personal Spacetime Stabilizer**: An essential safety device required for player teleportation.
    *   **[item=chuansongmen-spacetime-shard] Unstable Spacetime Shard**: A by-product of teleportation and the key consumable for maintaining the power grid. It can also be crafted via an inefficient emergency recipe in a Centrifuge.
3.  **Build the Portal**:
    *   Craft your first [item=chuansongmen] **Portal** using an expensive engineering recipe.
4.  **Pair & Use**:
    *   Place a portal at each of the two locations you wish to connect.
    *   Click on one portal, and in the opened GUI, select the other portal from the dropdown menu and click "Pair".
    *   Lay train tracks onto the portal's platform.
    *   Embark on your first spacetime jump!

## Resources & Consumption (in Consumption Mode)

*   **Train Teleport**: Consumes **1x [item=chuansongmen-exotic-matter] Exotic Matter** per trip.
*   **Player Teleport**: Consumes **1x [item=chuansongmen-exotic-matter] Exotic Matter** and **1x [item=chuansongmen-personal-stabilizer] Personal Spacetime Stabilizer** per trip.
*   **Power Grid Maintenance**: After connecting the remote power grid, the portal network will continuously consume **[item=chuansongmen-spacetime-shard] Unstable Spacetime Shards**. The default rate is 2 shards per minute (1 per portal), adjustable in the mod settings.
*   **Resource Return**: Each successful train or player teleportation returns **3x [item=chuansongmen-spacetime-shard] Unstable Spacetime Shards** in the output inventory.

## Compatibility

*   **Space Exploration (SE)**: Fully compatible. When SE is present, this mod's teleportation logic coexists harmoniously with SE's mechanics.
*   **Cybersyn**: Deep compatibility is provided.
    *   **With SE**: Cybersyn can use the portals as space elevators for fully automatic cross-surface dispatching.
    *   **Without SE**: Due to limitations within Cybersyn, **fully automatic** cross-surface dispatching is **not available**. However, players can **manually** add portal stations to a train's schedule. This mod includes an "ID Loss Fix" to ensure Cybersyn can correctly track the train after teleportation.

## Acknowledgements

*   **Earendel**: For the great **Space Exploration** mod, which was the entire inspiration for this project.
*   **Mami**: For the powerful **Cybersyn** mod and for the invaluable guidance provided on compatibility issues.
*   **The Players**: Thank you for using this mod, and you are welcome to provide any feedback and suggestions!

## Future Plans

*   Implement a dedicated technology tree to integrate all recipes into the game's progression.
*   Improve compatibility with Cybersyn in a non-SE environment (if possible).

<br><hr><br>

## [English](#railjump-轨道跃遷站) | 简体中文 版本

# RailJump (轨道跃迁站)

_一个允许火车和工程师在遥远的两个点之间瞬间移动的传送门模组。_

[Factorio Mod Portal Link](https://mods.factorio.com/mod/zzzzz) | [GitHub Repository](https://github.com/VariousTrick/railjump)

---

## 目录

*   [模组介绍](#模组介绍)
*   [核心功能](#核心功能)
*   [如何开始](#如何开始)
*   [资源与消耗](#资源与消耗)
*   [兼容性](#兼容性)
*   [鸣谢](#鸣谢)
*   [未来计划](#未来计划)

---

## 模组介绍

**轨道跃迁站 (RailJump)** 为您的工厂带来了终局的物流革命。本模组的设计灵感完全来源于 Earendel 的 Space Exploration (太空探索)，并致力于将“太空电梯”这一宏伟概念，以一种独立的、与原版游戏和其他大型模组兼容的方式，带给所有Factorio工程师。

您将能够建造巨大的传送门，将它们配对，并在整个星球甚至不同星球之间，建立起瞬时的火车运输网络。

**重要声明**: 本模组的开发过程完全由AI（人工智能）辅助完成，开发者本人主要扮演“导演”和“测试者”的角色。这是一个探索AI辅助开发的实验性项目。如果您对Mod的设计或平衡性有任何建议，欢迎随时提出，我们将继续与AI一同迭代和完善。

## 核心功能

*   **即时火车传送**: 将整列火车（包括其货物、流体、装备和乘客）从一个传送门瞬间传送到其配对的另一个传送门。
*   **玩家传送**: 工程师也可以通过传送门进行快速的个人旅行。
*   **跨空间电网**: 配对并连接的传送门可以共享同一个电网，让您可以将电力从主基地，无损耗地传输到遥远的哨站。
*   **两种游戏模式**:
    *   **有消耗模式 (默认)**: 传送、维持电网都需要消耗专属的后期资源，为游戏带来新的物流挑战。
    *   **无消耗模式**: 对于喜欢“沙盒”或“创意”模式的玩家，可以关闭所有消耗，专注于建设和规划。
*   **可配置**: 游戏内的Mod设置菜单，允许您实时调整电网的维持成本，以及是否显示相关的警告信息。

## 如何开始

1.  **研究科技**: (此部分待未来添加，目前所有配方均直接可用)
2.  **制造核心材料**:
    *   **[item=chuansongmen-exotic-matter] 奇异物质**: 传送的核心燃料，需要在**离心机**中通过复杂的终局配方生产。
    *   **[item=chuansongmen-personal-stabilizer] 个人时空稳定器**: 传送玩家时的必备安全装置。
    *   **[item=chuansongmen-spacetime-shard] 不稳定的时空碎片**: 传送后的副产品，也是维持电网的关键消耗品。您也可以通过一个低效的紧急配方在离心机中生产它。
3.  **建造传送门**:
    *   通过一个昂贵的工程配方，制造出您的第一个 [item=chuansongmen] **传送门**。
4.  **配对与使用**:
    *   在您想连接的两个地点分别放置传送门。
    *   点击一个传送门，在打开的GUI界面中，从下拉菜单里选择您想配对的另一个传送门，然后点击“配对”。
    *   将火车轨道铺设进传送门的平台。
    *   开始您的第一次时空跃迁！

## 资源与消耗 (有消耗模式)

*   **火车传送**: 每次传送消耗 **1x [item=chuansongmen-exotic-matter] 奇异物质**。
*   **玩家传送**: 每次传送消耗 **1x [item=chuansongmen-exotic-matter] 奇异物质** 和 **1x [item=chuansongmen-personal-stabilizer] 个人时空稳定器**。
*   **电网维持**: 连接远程电网后，传送门网络会持续消耗 **[item=chuansongmen-spacetime-shard] 不稳定的时空碎片**。默认速率为每分钟2个（每个传送门1个），可在Mod设置中调整。
*   **资源返还**: 每次成功的火车或玩家传送，都会在产出栏中返还 **3x [item=chuansongmen-spacetime-shard] 不稳定的时空碎片**。

## 兼容性

*   **Space Exploration (SE)**: 完全兼容。当SE存在时，本模组的传送逻辑会与SE的机制和谐共存。
*   **Cybersyn**: 提供了深度兼容。
    *   **在有SE时**: Cybersyn能够将传送门作为太空电梯进行全自动的跨地表调度。
    *   **在没有SE时**: 由于Cybersyn自身的限制，**全自动**的跨地表调度**不可用**。但是，玩家可以**手动**将传送门站点添加到火车时刻表中，本模组已包含“ID丢失修复”，可确保Cybersyn在传送后能继续正确追踪列车。

## 鸣谢

*   **Earendel**: 感谢其伟大的 **Space Exploration** Mod，它是我这个项目的全部灵感来源。
*   **Mami**: 感谢其强大的 **Cybersyn** Mod，以及他在兼容性问题上提供的宝贵指导。
*   **各位玩家**: 感谢您使用本模组，并欢迎您提出任何反馈和建议！

## 未来计划

*   增加独立的科技树，将所有配方整合到游戏进程中。
*   完善与Cybersyn在无SE环境下的兼容性（如果可能的话）。