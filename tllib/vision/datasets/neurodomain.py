import os

from tllib.vision.datasets import ImageList


class NeuroDomainVegFru(ImageList):
    CLASSES = ['apple', 'banana', 'pineapple', 'pomegranate', 'pumpkin'] # OR leave it to auto-detect if you prefer

    def __init__(self, root, task, download=False, **kwargs):
        # Map the TLLib 'split' names to your specific text files
        # We map 'train' to your neuro data and 'test' to vegfru
        if task not in self.domains():
            raise NotImplementedError("Not recognized task: {}".format(task))

        super(NeuroDomainVegFru, self).__init__(
            root,
            # If you don't want to hardcode classes, you can pass classes=None
            # but it's safer to define them to ensure mapping is correct.
            classes=self.CLASSES,
            data_list_file=os.path.join(root, f'{task}_list.txt'),
            **kwargs
        )

    @classmethod
    def domains(cls):
        # These are the names you will use in the -s and -t flags
        return ['neurodomain', 'vegfru-test']