import os
import sys
import json
import random
from zlib import adler32
from hashlib import md5

import tensorflow
from numpy.random import seed as numpy_seed
from keras import Model, backend as K
from keras.utils import plot_model
from keras.layers import Dense, Reshape, Concatenate
from .environment import StatelessEnv
from .parser import build_model as parser_model_build
from .rl_patches import TrainEpisodeLogger, DQNAgent

from rl.policy import BoltzmannQPolicy
from rl.memory import SequentialMemory
from rl.processors import MultiInputProcessor


def main():
    real_stdout = sys.stdout
    sys.stdout = sys.stderr  # Trick debug prints to output to stderr

    json_conf, weights_file, model_image_file = init()
    dqn, environment = build_model(json_conf)

    plot_model(dqn.model, to_file=model_image_file.format(pid=os.getpid()))

    if os.path.isfile(weights_file):
        dqn.load_weights(weights_file)
    else:
        iterations = train(environment, dqn)
        print('iterations = {iterations}'.format(iterations=iterations), file=real_stdout)

    validation_score = validate(environment, dqn)
    test_score = test(environment, dqn)

    print('score = {result}'.format(result=validation_score), file=real_stdout)
    print('display_score = {result}'.format(result=test_score), file=real_stdout)

    dqn.save_weights(weights_file, overwrite=True)

    environment.close()
    K.get_session().close()


def init():
    config_line = sys.stdin.readline()
    config = json.loads(config_line)

    short_hash = md5(config_line.encode('utf-8')).hexdigest()[0:10]
    # numpy_seed(config.get('seed', adler32(config_line.encode('utf-8'), 1337)))

    weights_file = 'results/weights-%s.h5f' % short_hash
    model_image_file = 'results/model-%s.png' % short_hash

    tensorflow_config = tensorflow.ConfigProto()
    tensorflow_config.gpu_options.allow_growth = True
    tensorflow_config.gpu_options.visible_device_list = "%d" % random.randint(0, 3)
    tensorflow_session = tensorflow.Session(config=tensorflow_config)
    K.set_session(tensorflow_session)

    return config, weights_file, model_image_file


def build_model(config):
    (internal_model, inputs) = parser_model_build(config)

    env = StatelessEnv(inputs, "runner/signals/", "-v" in sys.argv)
    actions_count = len(env.action_space)

    reshaped_outputs = [Reshape((-1,))(output) for output in internal_model.outputs]
    concatenated_outputs = Concatenate(-1)(reshaped_outputs) if len(reshaped_outputs) > 1 else reshaped_outputs[0]
    dense_transform = Dense(actions_count)(concatenated_outputs)
    outer_model = Model(inputs=internal_model.inputs, outputs=dense_transform)

    memory = SequentialMemory(limit=4000, window_length=config['window_length'])
    policy = BoltzmannQPolicy()
    dqn = DQNAgent(
        model=outer_model,
        nb_actions=actions_count,
        memory=memory,
        nb_steps_warmup=100,
        target_model_update=0.01,
        policy=policy,
        processor=MultiInputProcessor(nb_inputs=len(inputs)) if len(inputs) > 1 else None,
    )

    dqn.compile(optimizer=internal_model.optimizer, metrics=['mae'])

    return dqn, env


def validate(env, dqn):
    env.set_mode("validation")
    dqn.test(env, nb_episodes=1, action_repetition=1, visualize=False)
    dqn.reset_states()
    return env.mode.last_result


def test(env, dqn):
    env.set_mode("test")
    dqn.test(env, nb_episodes=1, action_repetition=1, visualize=False)
    dqn.reset_states()
    return env.mode.last_result


def learn(env, dqn, learning_episodes):
    env.set_mode("learning")
    dqn.fit(
        env,
        nb_steps=env.mode.steps * learning_episodes,
        action_repetition=1,
        visualize=False,
        verbose=0,
        callbacks=[TrainEpisodeLogger()]
    )
    dqn.reset_states()


def train(env, dqn):
    # Steps
    max_iterations = 200
    iteration_learning_episodes = 2

    # Policy (exploration versus exploitation of actions)
    final_tau = 0.7

    # Early-stopping (will stop if (current - last) / (last - second_to_last) < stopping_difference_ratio)
    stopping_difference_ratio = 0.5
    patience = 2

    # IDEA: Save weights from X iterations ago, and revert to them after early-stopping ends
    # The rationale is that we have to find the exact start of the overfit, otherwise validation/test perf will suffer

    # Internal variables
    iterations = 0
    last_score = 0.0
    last_difference = 1.0
    stopping_episodes = 0
    policy_tau_change = final_tau ** (1 / max_iterations)

    for i in range(max_iterations):
        iterations += 1
        dqn.policy.tau *= policy_tau_change

        learn(env, dqn, iteration_learning_episodes)

        current_score = validate(env, dqn)

        current_difference = current_score - last_score
        if abs(current_difference) < 0.1:
            current_difference = 0.1

        if current_difference / last_difference < stopping_difference_ratio:
            stopping_episodes += 1
            if stopping_episodes > patience:
                break
        else:
            stopping_episodes = 0

        last_score = current_score
        last_difference = current_difference

    return iterations


if __name__ == '__main__':
    main()
