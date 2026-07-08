#! /bin/python3

import os
import sys
import json
import shutil
import pprint
import filecmp
import hashlib
import tempfile
import difflib
import logging
import argparse
import traceback
import subprocess

logger = logging.getLogger("Test Runner")

keep_artifacts = False
executor_wrapper = ""
translate_only = False
drop_compile_flags = []

# Source: https://stackoverflow.com/questions/845276/how-to-print-the-comparison-of-two-multiline-strings-in-unified-diff-format
def unified_diff(text1, text2):
    # Ensure that the diff outputs correctly even when no output is given
    if text1 is None:
        text1 = ""
    if text2 is None:
        text2 = ""

    text1 = text1.splitlines(1)
    text2 = text2.splitlines(1)

    diff = difflib.unified_diff(text1, text2)

    return ''.join(diff)

class ExecutionError(Exception):
    def __init__(self, command, stdout, stderr):
        self.message = f"Error when executing {' '.join(command)}"
        self.stdout = stdout
        self.stderr = stderr
        super().__init__(self.message)

    def __str__(self):
        return self.message

class Tester:
    def __init__(self, txlat_path, input_bin, config = ""):
        self.artifacts = []
        self.txlat_path = txlat_path
        self.input_bin = input_bin

        if not os.path.isfile(self.txlat_path):
            raise ValueError(f"txlat does not exist at path: {self.txlat_path}")

        if not os.path.isfile(self.input_bin):
            raise ValueError(f"input binary does not exist at path: {self.input_bin}")

        env = os.environ.copy()

        self.config = {
            'compile_flags': [],
            'compile_environment': env, # default environment same as tester's
            'compile_artifacts': [],
            'compile_artifact_reference': {},
            'runtime_flags': [],
            'runtime_environment': env, # default environment same as tester's
            'expected_stdout': None,
            'expected_stderr': None,
            'expected_stdout_sha256': None,
            'expected_stderr_sha256': None,
            'expected_status': 0,
            'produced_artifacts': []
        }

        if not os.path.isfile(config):
            logger.warning(f"Config file does not exist at path \"{config}\"; "
                            "executing test in default configuration")
        else:
            self.parse_config(config)
            term_size_tuple = shutil.get_terminal_size(fallback=(200, 100))
            term_width = term_size_tuple[0]
            if term_width > 5:
                term_width -= 5

        for flag in drop_compile_flags:
            self.config['compile_flags'] = [
                existing for existing in self.config['compile_flags'] if existing != flag
            ]

        for extra in extra_runtime_env:
            key, value = extra.split('=')
            self.config['runtime_environment'][key] = value

        logger.info(f"Executing test with config:\n{pprint.pformat(self.config, width=term_width)}")


    def run(self):
        logger.info("Translating input binary")

        translated = self.compile()
        self.config["produced_artifacts"].append(translated)

        # TODO: generalize this to check artifacts for runtime execution too
        for artifact in self.config['compile_artifacts']:
            # Check artifact exists
            if not os.path.exists(artifact):
                raise ValueError(f"Artifact {artifact} not produced after compilation")

            # Check if artifact matches reference
            if artifact in self.config['compile_artifact_reference'].keys():
                reference = self.config['compile_artifact_reference'][artifact]
                if not filecmp.cmp(artifact, reference, shallow=False):
                    output_bytes = open(artifact, 'r').read()
                    reference_bytes = open(reference, 'r').read()
                    logger.error(f"Artifact {artifact} does not match reference {reference}, \
                                 diff:\n{unified_diff(reference_bytes, output_bytes)}\n")

        logger.info("Translation successful")

        if translate_only:
            return

        logger.info(f"Executing transated binary: {translated}")
        stdout, stderr = self.execute(translated)

        self.compare_output(self.config["expected_stdout"], stdout)
        self.compare_output(self.config["expected_stderr"], stderr)
        self.compare_output_hash("stdout", self.config["expected_stdout_sha256"], stdout)
        self.compare_output_hash("stderr", self.config["expected_stderr_sha256"], stderr)

    def __del__(self):
        if keep_artifacts:
            return

        for output_file in self.config["produced_artifacts"]:
            if os.path.exists(output_file):
                os.remove(output_file)

    def compile(self):
        fd, output_file = tempfile.mkstemp(prefix=os.path.basename(self.input_bin) + ".",
                                           suffix=".out", dir=os.getcwd())
        os.close(fd)
        os.remove(output_file)
        compile_command = [self.txlat_path, "--input", self.input_bin, "--output", output_file,
                           *self.config["compile_flags"]]
        proc = subprocess.run(compile_command, env=self.config['compile_environment'],
                              capture_output=True, text=True, errors="ignore")
        if proc.returncode != 0:
            raise ExecutionError(compile_command, proc.stdout, proc.stderr)

        return output_file

    def execute(self, binary):
        # TODO: include runtime environment
        execute_command = [*executor_wrapper, binary, *self.config["runtime_flags"]]
        logger.debug(f"Execution command: {execute_command}")

        shell = False
        capture_output = True
        if executor_wrapper != "":
            shell = True
            capture_output = False

        proc = subprocess.run(execute_command, env=self.config['runtime_environment'],
                              capture_output=capture_output, text=True, shell=shell, errors="ignore")

        expected_returncode = self.config["expected_status"]
        if proc.returncode != expected_returncode:
            logger.error(f"Exit code {proc.returncode} different from expected exit code {expected_returncode}")
            raise ExecutionError(execute_command, proc.stdout, proc.stderr)

        logger.info("Completed execution successfully")

        return proc.stdout, proc.stderr

    def parse_config(self, config):
        with open(config, 'r') as f:
            config_data = json.load(f)

            for key in self.config.keys():
                if key in config_data:
                    if self.config[key] is None:
                        self.config[key] = config_data[key]
                    elif isinstance(self.config[key], dict):
                        self.config[key].update(config_data[key])
                    else:
                        self.config[key].extend(config_data[key])

    def compare_output(self, reference, output):
        if reference is not None:
            reference = '\n'.join(reference)
            if reference != output:
                logger.error("Output differs")
                logger.error(f"Reference:\n{reference}")
                logger.error(f"Actual:\n{output}")

                diff = unified_diff(reference, output)
                logger.error(f"Diff:\n{diff}")
                exit(2)
            logger.info("Output matches!")

    def compare_output_hash(self, stream_name, reference_hash, output):
        if reference_hash is not None:
            actual_hash = hashlib.sha256(output.encode()).hexdigest()
            if actual_hash != reference_hash:
                logger.error(f"{stream_name} sha256 differs")
                logger.error(f"Reference: {reference_hash}")
                logger.error(f"Actual:    {actual_hash}")
                logger.error(f"Actual {stream_name}:\n{output}")
                exit(2)
            logger.info(f"{stream_name} sha256 matches!")

def parse_arguments():
    parser = argparse.ArgumentParser()
    parser.description = 'Arancini binary execution test runner'

    # Specification of the concrete test trace
    parser.add_argument('-i', '--input',
                        required=True,
                        help='Path to input x86 binary to translate and then execute')

    parser.add_argument('-t', '--txlat', '--translator',
                        required=True,
                        help='Path to translator (txlat) program')

    parser.add_argument('-c', '--config',
                        required=False,
                        default="",
                        help='Path to (JSON) configuration file for the tester')

    parser.add_argument('--log-level',
                        required=False,
                        default="WARNING",
                        choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
                        help='Logging level for tester')

    parser.add_argument('--keep-artifacts',
                        required=False,
                        default=False,
                        action='store_true',
                        help='Do not remove artifacts generated during test (including translated binaries)')

    parser.add_argument('--execute-under',
                        required=False,
                        default='',
                        nargs=1,
                        help='Specify a wrapper for executing the translated binary (.e.g \"gdb --args\"')

    parser.add_argument('--extra-runtime-env',
                        required=False,
                        default='',
                        nargs='+',
                        help='KEY=VALUE strings to be added to environment during translated program \
                        execution (in addition to those added via -c and the default)')

    parser.add_argument('--translate-only',
                        required=False,
                        default=False,
                        action='store_true',
                        help='Invoke translator for input binary and exit (can be combined with --keep-artifacts to get the translator output')

    parser.add_argument('--drop-compile-flag',
                        required=False,
                        default=[],
                        action='append',
                        help='Remove a compile flag loaded from the JSON config before translation')

    args = parser.parse_args()

    # TODO: refactor parsing here to directly store those flags
    global keep_artifacts
    keep_artifacts = args.keep_artifacts

    global executor_wrapper
    executor_wrapper = args.execute_under

    global extra_runtime_env
    extra_runtime_env = args.extra_runtime_env

    global translate_only
    translate_only = args.translate_only

    global drop_compile_flags
    drop_compile_flags = args.drop_compile_flag

    return args

if __name__ == "__main__":
    # Parse command-line flags
    args = parse_arguments()

    # Configure logger
    logging.basicConfig(level=getattr(logging, args.log_level),
                        format="[%(name)s][%(levelname)s] %(message)s")

    try:
        tester = Tester(args.txlat, args.input, args.config)
        tester.run()
    except ExecutionError as e:
        # Disable traceback
        sys.tracebacklimit=0

        logging.exception(f"Test failed: {str(e)}")
        logging.error(f"Contents of STDOUT:\n{e.stdout}")
        logging.error(f"Contents of STDERR:\n{e.stderr}")
        exit(2)
    except Exception as f:
        logging.exception(f"Test failed: {str(f)}")
        logging.error(f"Traceback:\n{traceback.format_exc()}")
        exit(2)

    exit(0)

