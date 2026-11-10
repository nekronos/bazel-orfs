"""Tests for orfs_flow's stage_exec_properties in private/flow.bzl.

A stage's exec_properties merge per key over the flow's, so a stage that
reserves CPUs or memory keeps the flow's platform properties. A stage
that reserves CPUs runs OpenROAD with NUM_CORES set to them, unless its
arguments set NUM_CORES.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("//private:flow.bzl", "num_cores_arguments", "stage_exec_properties_of")

def _merge_per_key_test(ctx):
    env = unittest.begin(ctx)
    flow = {"OSFamily": "linux", "cpu_count": "1"}
    stages = {"grt": {"cpu_count": "8", "memory_kb": "16777216"}}
    asserts.equals(
        env,
        {"OSFamily": "linux", "cpu_count": "8", "memory_kb": "16777216"},
        stage_exec_properties_of("grt", flow, stages),
        "the stage's keys override the flow's, the flow's other keys stay",
    )
    asserts.equals(
        env,
        flow,
        stage_exec_properties_of("place", flow, stages),
        "a stage without an entry takes the flow's",
    )
    asserts.equals(
        env,
        {"cpu_count": "8", "memory_kb": "16777216"},
        stage_exec_properties_of("grt", None, stages),
        "a flow without exec_properties takes the stage's",
    )
    return unittest.end(env)

def _num_cores_test(ctx):
    env = unittest.begin(ctx)
    asserts.equals(
        env,
        {"NUM_CORES": "8", "PLACE_DENSITY": "0.65"},
        num_cores_arguments({"PLACE_DENSITY": "0.65"}, {"cpu_count": "8"}),
        "NUM_CORES follows the reserved CPUs",
    )
    asserts.equals(
        env,
        {"NUM_CORES": "2"},
        num_cores_arguments({"NUM_CORES": "2"}, {"cpu_count": "8"}),
        "a NUM_CORES the arguments set is kept",
    )
    asserts.equals(
        env,
        {"PLACE_DENSITY": "0.65"},
        num_cores_arguments({"PLACE_DENSITY": "0.65"}, {"OSFamily": "linux"}),
        "no cpu_count, no NUM_CORES",
    )
    asserts.equals(
        env,
        {},
        num_cores_arguments({}, None),
        "no exec_properties, no NUM_CORES",
    )
    return unittest.end(env)

merge_per_key_test = unittest.make(_merge_per_key_test)
num_cores_test = unittest.make(_num_cores_test)

def stage_exec_properties_test_suite(name):
    unittest.suite(
        name,
        merge_per_key_test,
        num_cores_test,
    )

_ExecPropertiesInfo = provider(
    doc = "The exec_properties attribute of the target under test.",
    fields = ["exec_properties"],
)

def _exec_properties_aspect_impl(_target, ctx):
    return [_ExecPropertiesInfo(exec_properties = ctx.rule.attr.exec_properties)]

_exec_properties_aspect = aspect(implementation = _exec_properties_aspect_impl)

def _num_cores_in_config(env):
    """The NUM_CORES values in the stage's config, the JSON the rule wrote."""
    values = []
    for action in analysistest.target_actions(env):
        # Only a FileWrite's content is the text the rule wrote; asking
        # another action for it makes bazel read a file at analysis time.
        if action.mnemonic != "FileWrite":
            continue
        if not [f for f in action.outputs.to_list() if f.path.endswith(".json")]:
            continue
        config = json.decode(action.content)
        if type(config) == "dict" and "NUM_CORES" in config:
            values.append(config["NUM_CORES"])
    return values

def _stage_exec_properties_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    asserts.equals(
        env,
        ctx.attr.expected_exec_properties,
        target[_ExecPropertiesInfo].exec_properties,
        "%s: the target's exec_properties" % target.label,
    )
    asserts.equals(
        env,
        [ctx.attr.num_cores] if ctx.attr.num_cores else [],
        sorted(set(_num_cores_in_config(env))),
        "%s: NUM_CORES in the stage's config" % target.label,
    )
    return analysistest.end(env)

stage_exec_properties_test = analysistest.make(
    _stage_exec_properties_test_impl,
    attrs = {
        "expected_exec_properties": attr.string_dict(),
        "num_cores": attr.string(),
    },
    extra_target_under_test_aspects = [_exec_properties_aspect],
)
