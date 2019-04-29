#! /usr/bin/env python

import glob
import numpy
from setuptools import setup, find_packages, Extension
from Cython.Build import cythonize

setup(
    name="simtrie",
    version="0.8.0",
    description="An efficient data structure for fast string similarity searches",
    author='Bernhard Liebl',
    author_email='poke1024@gmx.de',
    url='https://github.com/poke1024/minitrie/',

    packages=find_packages(),

    ext_modules=cythonize([
        Extension(
            name="simtrie",
            sources=['simtrie/simtrie.pyx'],
            extra_compile_args=["-O3", "-std=c++14"],
            include_dirs=['lib', numpy.get_include()],
            language="c++",
        )
    ]),

    install_requires=[
        "numpy>=1.15.0",
        "msgpack>=0.6.1",
        "tqdm>=4.31.0"
    ],

    python_requires=">=3.7",

    classifiers=[
        'Development Status :: 4 - Beta',
        'Intended Audience :: Developers',
        'Intended Audience :: Science/Research',
        'License :: OSI Approved :: MIT License',
        'Programming Language :: Cython',
        'Programming Language :: Python',
        'Programming Language :: Python :: 3.7',
        'Programming Language :: Python :: Implementation :: CPython',
        'Topic :: Software Development :: Libraries :: Python Modules',
        'Topic :: Scientific/Engineering :: Information Analysis',
        'Topic :: Text Processing :: Linguistic',
    ],
)
