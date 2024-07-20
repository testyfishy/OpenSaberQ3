extends Node

const BEAT_DISTANCE := 4.0
const LANE_DISTANCE := 0.6
var LANE_X := PackedFloat64Array([-0.9, -0.3, 0.3, 0.9])
var LAYER_Y := PackedFloat64Array([0.8, 1.4, 2.0])
const MISS_Z := 2.5
var CUBE_ROTATIONS := PackedFloat64Array([PI, 0.0, -TAU*0.25, TAU*0.25, -TAU*0.375, TAU*0.375, -TAU*0.125, TAU*0.125, 0.0])
const APPDATA_PATH := "user://OpenSaber/"
