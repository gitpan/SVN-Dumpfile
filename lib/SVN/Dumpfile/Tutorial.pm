
=pod

=head1 SVN::Dumpfile Tutorial

This tutorial describes the use of the SVN::Dumpfile package to access,
manipulate and create Subversion dumpfiles.

=head2 Basics

Subversion repositories can be exported in a file format independent from the
used database backend which is compatible to older and future versions. This
files are called 'dumpfiles' and can be generated by the C<svnadmin dump> 
command and imported with C<svnadmin load>.

The SVN::Dumpfile module represents one dumpfile and provides all methods to
access all of its contained elements but also to generate new dumpfiles out of
existing ones or from other sources.


=head3 Dumpfile format

The dumpfile format as specified by the Subversion team in
L<http://svn.collab.net/repos/svn/trunk/notes/dump-load-format.txt> looks like
this:

    --------------------
    Dumpfile Headers
    [ Revision node 0 ]
    Revision node
    Node
    Node
    ...
    Revision node
    Node
    Node
    ...
    --------------------

The dumpfile starts with a few file headers specifing the used version and the
an unique ID. The rest is build from revision nodes followed by zero, one or 
more normal nodes. Only revision nodes for revision #0 and placeholder for 
deleted revisions are not followed by normal nodes, but normally all others are.


=head3 Subversion Nodes

As mentioned before there are two different kinds of nodes in subversion
dumpfiles: normal nodes and revision nodes. Revision nodes start a new revision
and only hold the revision number and properties -- author, date and log entry.
Normal nodes hold the informations for one single change to a single file or
directory. This change can be to add, modify or delete the file or directory
and/or the properties of it.

In general nodes contain of three different parts: headers, properties and
content, in this order. Only the header part is mandatory, the other two can be
missing in the case the node has no properties and/or content. The headers
provide information about the kind of the node and about the length of the
properties and content.  Therefor if the both are changed some headers have to
be recalculated.

The nodes returned by the SVN::Dumpfile method read_node() (aliases: get_node()
next_node()) are objects from the SVN::Dumpfile::Node class which holds one
object each from the classes SVN::Dumpfile::Node::Headers,
SVN::Dumpfile::Node::Properties and SVN::Dumpfile::Node::Content.
The node object provides many methods to access the underlying objects, so that
they don't have to be accessed directly most of the time.


=head3 Node Headers

The following headers are known to exist in Subversion dumpfiles and should be
known to the user to get the most out of this package.

Note that all length and checksum headers are automatically recalculated when
the node is marked as changed by using the changed() method.

=over 4

=item Revision-number: non-negative integer

The first header in, and only in, a revision node gives the revision number. All
following normal nodes belong to this revision until the next revision node.

=item Node-path: unix/style/path

This header gives the path of the file, symlink or directory described by the 
current normal node. Note that no leading or trailing (for directories) slash is
included.

=item Node-kind: ( file | dir )

This header specifies if the node describes a file or a directory. Unix symbolic
links are handled as files with special a special property set.

=item Node-action: ( add | delete | change )

The performed action on the described file or directory, which can be added,
deleted or changed. Note that any change in properties (add, delete or change)
of an already existing file or directory are marked as 'change' action.

=item Node-copyfrom-rev: non-negative integer

If a file or directory was copied from another the source revision number of the
original is given by this header. This header must be used in combination with
Node-copyfrom-path.

=item Node-copyfrom-path: unix/style/path

If a file or directory was copied from another the path of the
original is given by this header. This header must be used in combination with
Node-copyfrom-rev.

=item Prop-delta: ( true | false )

This header specifies if the properties are included as delta to the last
changed revision of the file or directory. If present it is normally set to
'true'. If not present the default value is 'false'.

=item Text-delta: ( true | false )

This header specifies if the content is included as delta to the last
changed revision of the file or directory. If present it is normally set to
'true'. If not present the default value is 'false'.

=item Prop-content-length: non-negative integer

This header gives the number of bytes of the properties block. If not present or
zero then the node has no properties or they did not got changed (if
'Prop-delta: true'). Because this length includes the "PROPS-END${NL}" marker a
value of 10 means that there is an empty properties block attached to the node.

=item Text-content-length: non-negative integer

This header gives the number of bytes of the content. If not present or zero
then the node has no content. This means normally that the node describes a
directory or an unmodified file copy.

=item Text-content-md5: MD5 sum from content (32 hex-digits)

This header specifies the MD5 (Message Digest 5) checksum of the content (in
binary, not ASCII form). If it is not correct the import of the dumpfile will be
aborted.

=item Text-copy-source-md5: MD5 sum from copied content (32 hex-digits)

If the node describes a copy process this header can be used to improve data
integrity. The MD5 is the same as given by the 'Text-content-md5' header of the
copied file.

=item Content-length: non-negative integer

This header gives the total number of bytes of the content, i.e. is the sum of
the 'Prop-content-length' and 'Text-content-length' headers.

=back


=head3 Subversion Properties

Properties can have any text as name and, like the content,
hold any kind of data either in text or binary form. They provide a handy way to
attach meta-data or other information to the files and directories.

Subversion itself uses a special set of properties to store basic but important
meta-data. All of these have the prefix 'svn:' which should not be used for any
user defined properties. The following svn properties are known to exists and
described briefly because they can influence how the dumpfile nodes are to be
handled. For more informations see the Subversion book at
L<http://svnbook.red-bean.com/en/1.1/ch07s02.html>.

=over 4

=item svn:keywords = Revision Rev LastChangedRev Date LastChangedDate Author
LastChangedBy HeadURL URL Id (any combination)

Specifies which keywords should be expanded inside the file. Note that the
dumped file content only includes the unexpanded file content. Some keywords
have multiple alternate names as listed above.

=item svn:mime-type = group/type

Provides the MIME type of the file. Binary files must have the correct type
set or 'application/octet-stream' if it isn't known. Text files like
source code doesn't have to have this property set, but if so it should be 
a type from the 'text/' group if no specific type is defined.

=item svn:eol-style = ( native | CRLF | LF | CR )

Specifies which end-of-line style should be used for text files. It is
recommended by the author of this Perl package to use 'native' wherever you can.
This results that text files are checked-out in the native style of the used
operation system. However, some file formats need a specific fixed style which
should not be changed to not corrupt the file.

=item svn:executable

Marks the file as executable if exists, i.e. the executable flag is set when the
file is checked-out on a Unix-like OS. The value is meaningless and can be
empty.


=item svn:special = ?

Set on 'file' nodes which actually describe symlinks or other special things.


=item svn:ignore = MULTI LINE LIST

Only applicable to directories this property specifies the ignore patterns to be
used for Subversion status reports.

=item svn:externals = MULTI LINE LIST

Lists links to external Subversion repository URLs.



=back


=head3 Basic methods

=head4 Open existing Dumpfile

    use SVN::Dumpfile;
    my $df = new SVN::Dumpfile;
    $df->open("mydumpfile.dump");


=head4 Access Dumpfile Headers

    $df->version()  # Dumpfile version, at the moment: 1, 2 or 3
    $df->uuid()     # Universal Unique IDentifier (for version >= 2)


=head4 Get Dumpfile Headers as printable String

    $df->as_string()


=head4 Read (next) Node from Dumpfile

    my $node = $df->read_node();
    # aliases: next_node() get_node()

=head4 Check if Revision Node or not

    if ($node->is_rev) {
        # Revision
    }
    else {
        # Normal node
    }


=head4 Check Existence of Node Parts

The existence of all three parts can, and should, be checked with the methods:

    $node->has_headers()
    $node->has_properties()
    $node->has_content()

While headers are mandartory there might not exists in a new created node which
was not read from a dumpfile but created by the user.


=head4 Access to Headers

To test if the node has a specific header use:

    $node->has_header('Some-Header')

Single headers can be read with

    $node->header('Some-Header')

and changed by providing a second argument or using the method as lvalue:

    $node->header('Some-Header', 'new value')
    $node->header('Some-Header') = 'new value'

=head4 Access to Properties

To test if the node has a specific property use:

    $node->has_property('Some-Property')

Single properties can be read with

    $node->property('Some-Property')

and changed by providing a second argument or using the method as lvalue:

    $node->property('Some-Property', 'new value')
    $node->property('Some-Property') = 'new value'

SVN::Dumpfile tries to maintain the exact string representation of
unmodified nodes to support before/after comparison. Because of this the order
of the properties must also be saved. New properties can be added to any
position using:

    $node->properties->add('property name', 'value', $position)

If $position is not given the property is added at the end.

=head4 Access to Content

The node content can be either text (ASCII, UTF-8, ...) or binary. In the
second case a 'svn:mime-type' property should (must?) be present and indicate
its type. In general the mime type 'application/octet-stream' is used, but all
other from the 'application' group should be considered binary. Actually only
types from the group 'text' can be safely considered text.

To test the mime type use

    $node->property('svn:mime-type')

The content is returned by

    $node->content()

and can be changed by providing an argument or using the method as lvalue:

    $node->content('new content')
    $node->content() = 'new content'


=head4 Marking the Node as changed

After changing the content or any properties the coresponding headers must be
recalculated. To force this mark the node as changed using:

    $node->changed();


=head4 Creating new Dumpfiles

New dumpfile can be created by the create() method. Because the file headers are
written immediately they must exist before the method is called. They can
be copied from another open dumpfile with copy():

    my $df2 = $df->copy();          # Copies file headers only
    $df2->create("newfile.dump");

=head4 Write Nodes to Dumpfile

Nodes can be written to new created dumpfiles with:

    $df2->write_node($node);

However they can also be printed to any file handle using:

    $node->as_string()


=head4 Close Dumpfile

All dumpfiles, open()-ed or create()-d ones, should be closed using close().

    $df->close();
    $df2->close();

There are, however, closed automatically when the dumpfile object is going out
of scope.


=head4 Access to Underlying Objects

If direct access to the underlying objects is needed they can be accessed by the
following methods which return blessed object references:

    $node->headers()      # Returns SVN::Dumpfile::Node::Headers object
    $node->properties()   # Returns SVN::Dumpfile::Node::Properties object
    $node->contents()     # Returns SVN::Dumpfile::Node::Contents object

=head2 Examples

=head3 Read existing Dumpfile and print it

    my $df = new SVN::Dumpfile;
    $df->open('file.dump');

    # Print dumpfile headers
    print $df->as_string;

    while ( my $node = $df->read_node ) {
        print $node->as_string;
    }

    $df->close();

=head3 Create new Dumpfile manually

    my $df = new SVN::Dumpfile ( version => 3 );
    # UUID will be created automatically
    $df->create('file.dump');

    my $rev;
    my $node;

    # [...]

    # Compact way to create nodes:

    # Create revision node
    $rev = SVN::Dumpfile::Node->newrev(
        number => 123,
        author => 'karlheinz',
        date   => '2006-05-10T13:31:40.486172Z',   # Can be any format accepted
                                                   # by Date::Parse
        log    => 'Changed X to Y. Added Z.'
    );

    $df->write_node($rev);

    # Create file node
    $node = SVN::Dumpfile::Node->new(
        headers => {
            'Node-path' => 'test/path',
            'Node-kind' => 'file',
            'Node-action' => 'add',
        },
        properties => {
            'svn:eol-style' => 'native',
            'svn:keywords' => 'Id Rev Author',
            'userprop' => "USER\n",
        },
        content => "Some ...\n...\n... content.\n",
    );

    # Note that the node has been marked as changed and content and property
    # specific headers will be recalculated when node is written.

    $df->write_node($node);

    # [...]


    # Other way to create nodes

    # Create revision node
    $rev = new SVN::Dumpfile::Node;

    $rev->header( 'Revision-number', 123 );
    $rev->property( 'svn:author', 'karlheinz' );
    $rev->property( 'date','2006-05-10T13:31:40.486172Z' );   # Must be correct
                                                              # format!
    $rev->property( 'log', 'Changed X to Y. Added Z.' );

    $rev->changed();

    $df->write_node($rev);


    # Create file node
    $node = new SVN::Dumpfile::Node;
    $node->header( 'Node-path', 'test/path' );
    $node->header( 'Node-kind', 'file' );
    $node->header( 'Node-action', 'add' );

    $node->property( 'svn:eol-style', 'native' );
    $node->property( 'svn:eol-style', 'native' );
    $node->property( 'svn:keywords', 'Id Rev Author' );
    $node->property( 'userprop', "USER\n" );

    $node->content("Some ...\n...\n... content.\n");

    $node->changed();

    $df->write_node($node);

    # [...]

    $df->close();


=cut
