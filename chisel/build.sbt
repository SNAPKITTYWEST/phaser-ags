// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2025 Ahmad Ali Parr / SnapKitty — https://github.com/SNAPKITTYWEST/phaser-ags
// build.sbt — Chisel 6.x + ChiselTest
// Phase: circuits → Chisel HDL

name := "phaser-ags-chisel"
version := "0.1.0"
scalaVersion := "2.13.12"

addCompilerPlugin("edu.berkeley.cs" % "chisel3-plugin" % ChiselVersion cross CrossVersion.full)
libraryDependencies ++= Seq(
  "edu.berkeley.cs" %% "chisel3" % ChiselVersion,
  "edu.berkeley.cs" %% "chiseltest" % "0.6.0" % "test",
  "org.scalatest" %% "scalatest" % "3.2.16" % "test"
)
