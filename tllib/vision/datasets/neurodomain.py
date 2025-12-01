import os
from typing import Optional

from tllib.vision.datasets import ImageList


class NeuroDomain(ImageList):
    CLASSES = ['apple', 'banana', 'pineapple', 'pomegranate', 'pumpkin']
    DOMAINS = {
        'neurodomain': ['train', 'val'],
        'vegfru': ['train', 'val', 'test'],
    }

    def __init__(self, root: str, task: str, split: str, download: bool = False, **kwargs):
        if task not in self.domains():
            raise NotImplementedError("Not recognized task: {}".format(task))

        if split not in self.DOMAINS[task]:
            raise NotImplementedError("Not recognized split: {}".format(split))

        super(NeuroDomain, self).__init__(
            root,
            classes=self.CLASSES,
            data_list_file=os.path.join(root, f'{task}_{split}_list.txt'),
            **kwargs
        )

    @classmethod
    def domains(cls):
        return cls.DOMAINS.keys()