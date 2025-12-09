# Cruise: DAG

Graph theory is an ancient and well-known subject. Its purpose is to study **graphs**, which are structures that model pairwise relationships between objects. These objects are called **vertices**, and the links between them are **edges**.

Looking closely, we can see that games naturally fit into the graph model:

* They consist of multiple systems (audio, logic, physics, rendering, etc.)
* These systems are linked by dependencies (e.g., rendering depends on physics)

In this context, we can model a game using a graph, but not just any graph: a **Directed Acyclic Graph (DAG)**, which is a type of graph with two key constraints:

* There are no cycles
* Edges have a direction, from node A to node B

Why does this matter?
Because it ensures there are no deadlocks or impossible execution paths when running systems in parallel. It also enforces a clear order of execution between systems.

More formally, we model our game as a set of systems linked by one-way dependencies, forming a DAG. Using a topological sort, we can compute the optimal execution order and even leverage parallelism for maximum efficiency.

This is a brief overview of how Cruise manages your games.
